//
//  Primus.m
//  Primus
//
//  Created by Nuno Sousa on 1/8/14.
//  Copyright (c) 2014 Seegno. All rights reserved.
//

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#endif

#import <libextobjc/EXTScope.h>
#import <objc/runtime.h>

#import "Primus.h"

typedef NS_ENUM(NSUInteger, PrimusEventPublishType) {
    PrimusEventPublishTypeEvent = 0,
    PrimusEventPublishTypeAcknowledgment = 1
};

// Public events
NSString * const PrimusEventReconnect = @"reconnect";
NSString * const PrimusEventReconnecting = @"reconnecting";
NSString * const PrimusEventOnline = @"online";
NSString * const PrimusEventOffline = @"offline";
NSString * const PrimusEventOpen = @"open";
NSString * const PrimusEventError = @"error";
NSString * const PrimusEventData = @"data";
NSString * const PrimusEventEnd = @"end";
NSString * const PrimusEventClose = @"close";
NSString * const PrimusEventTimeout = @"timeout";

// Internal events - incoming
NSString * const PrimusEventIncomingOpen = @"incoming::open";
NSString * const PrimusEventIncomingData = @"incoming::data";
NSString * const PrimusEventIncomingPong = @"incoming::pong";
NSString * const PrimusEventIncomingEnd = @"incoming::end";
NSString * const PrimusEventIncomingError = @"incoming::error";

// Internal events - outgoing
NSString * const PrimusEventOutgoingOpen = @"outgoing::open";
NSString * const PrimusEventOutgoingData = @"outgoing::data";
NSString * const PrimusEventOutgoingPing = @"outgoing::ping";
NSString * const PrimusEventOutgoingEnd = @"outgoing::end";
NSString * const PrimusEventOutgoingReconnect = @"outgoing::reconnect";

@interface Primus ()

@property (nonatomic, assign) BOOL unreachablePending;

@end

@implementation Primus

@synthesize request = _request;
@synthesize options = _options;
@synthesize primusDelegate = _primusDelegate;

- (id)init
{
    [self doesNotRecognizeSelector:_cmd];

    return nil;
}

- (id)initWithURL:(NSURL *)url
{
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];

    return [self initWithURLRequest:request];
}

- (id)initWithURL:(NSURL *)url options:(PrimusConnectOptions *)options
{
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];

    return [self initWithURLRequest:request options:options];
}

- (id)initWithURLRequest:(NSURLRequest *)request
{
    PrimusConnectOptions *options = [[PrimusConnectOptions alloc] init];

    return [self initWithURLRequest:request options:options];
}

- (id)initWithURLRequest:(NSURLRequest *)request options:(PrimusConnectOptions *)options
{
    self = [super init];

    if (self) {
        _request = request;
        _options = options;
        _attemptOptions = nil;
        _reconnectOptions = options.reconnect;
        _buffer = [[NSMutableArray alloc] init];
        _transformers = [[PrimusTransformers alloc] init];
        _timers = [[PrimusTimers alloc] init];
        _reach = [Reachability reachabilityForInternetConnection];
        _online = YES;

        [self bindRealtimeEvents];
        [self bindNetworkEvents];
        [self bindSystemEvents];

        if (!options.manual) {
            _timers.open = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(open) userInfo:nil repeats:NO];
        }
    }

    return self;
}

/**
 * Setup internal listeners.
 */
- (void)bindRealtimeEvents
{
    //
}

/**
 * Listen for network change events
 */
- (void)bindNetworkEvents
{
    __weak typeof(self) weakSelf = self;

    _reach.reachableBlock = ^(Reachability *reach) {
        weakSelf.unreachablePending = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;

            strongSelf->_online = YES;

            if ([strongSelf.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
                [strongSelf.primusDelegate onEvent:PrimusEventOnline
                                          userInfo:nil];

            if ([strongSelf.options.reconnect.strategies containsObject:@(kPrimusReconnectionStrategyOnline)]) {
                [strongSelf reconnect];
            }
        });
    };

    _reach.unreachableBlock = ^(Reachability *reach) {
        weakSelf.unreachablePending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;

            if (!strongSelf.unreachablePending)
                return;

            strongSelf->_online = NO;

            if ([strongSelf.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
                [strongSelf.primusDelegate onEvent:PrimusEventOffline
                                          userInfo:nil];

            [strongSelf end];
        });
    };

    [_reach startNotifier];
}

/**
 * Listen for app state change events
 */
- (void)bindSystemEvents
{
#if __has_include(<UIKit/UIKit.h>)
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (NO == self.options.stayConnectedInBackground) {
            return;
        }

        // Send a keep-alive ping every 10 minutes while in background
        [UIApplication.sharedApplication setKeepAliveTimeout:600 handler:^{
            [_timers.ping fire];
        }];
    }];

    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [UIApplication.sharedApplication clearKeepAliveTimeout];
    }];
#endif
}

/**
 * Initialise and setup the transformer and parser.
 */
- (void)initialize
{
    Class transformerClass = self.options.transformerClass;
    Class parserClass = self.options.parserClass;

    if (self.options.autodetect) {
        // If there is no transformer set, request the /spec endpoint and
        // map the server-side transformer to our client-side one.
        // Also, since we already have that information, set the parser as well.
        NSDictionary *spec = [self getJSONData:[self.request.URL URLByAppendingPathComponent:@"spec"]];

        if (!transformerClass) {
            transformerClass = NSClassFromString([self.transformers mapTransformer:spec[@"transformer"]]);
        }

        if (!parserClass) {
            parserClass = NSClassFromString([spec[@"parser"] uppercaseString]);
        }

        // Subtract 10 seconds from the maximum server-side timeout, as per the
        // official Primus server-side documentation.
        NSTimeInterval timeout = ((NSNumber *)spec[@"timeout"]).doubleValue - 10e3;

        self.options.ping = MAX(MIN(self.options.ping, timeout / 1000.0f), 0);
    }

    // If there is no parser set, use JSON as default
    if (!parserClass) {
        parserClass = NSClassFromString(@"JSON");
    }

    if (transformerClass && ![transformerClass conformsToProtocol:@protocol(TransformerProtocol)]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Transformer does not implement TransformerProtocol." userInfo:nil];
    }

    if (parserClass && ![parserClass conformsToProtocol:@protocol(ParserProtocol)]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Parser does not implement ParserProtocol." userInfo:nil];
    }

    // Initialize the transformer and parser
    self.options.transformerClass = transformerClass;
    self.options.parserClass = parserClass;

    if (!_transformer) {
        _transformer = [[self.options.transformerClass alloc] initWithPrimus:self];
    }

    if (!_parser) {
        _parser = [[self.options.parserClass alloc] init];
    }

    [self emit:@"initialised", self.transformer, self.parser];
}

/**
 * Synchronously retrieve JSON data from a URL.
 */
- (NSDictionary *)getJSONData:(NSURL *)url
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];

    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];

    if (200 != response.statusCode){
        return nil;
    }

    return [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
}

/**
 * Establish a connection with the server. When this function is called we
 * assume that we don't have any open connections. If you do call it when you
 * have a connection open, it could cause duplicate connections.
 */
- (void)open
{
    [self initialize];

    if (!self.transformer) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"No transformer specified." userInfo:nil];
    }

    if (!self.parser) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"No parser specified." userInfo:nil];
    }

    // Resolve and instantiate plugins
    NSMutableDictionary *plugins = [[NSMutableDictionary alloc] init];

    for (NSString *pluginName in self.options.plugins.allKeys) {
        id pluginClass = self.options.plugins[pluginName];
        id plugin = nil;

        if ([pluginClass isKindOfClass:NSString.class]) {
            plugin = [NSClassFromString(pluginClass) alloc];
        }

        if (class_isMetaClass(object_getClass(pluginClass))) {
            plugin = [(Class)pluginClass alloc];
        }

        if (![plugin conformsToProtocol:@protocol(PluginProtocol)]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Plugin should be a class whose instances conform to PluginProtocol" userInfo:nil];
        }

        plugins[pluginName] = [plugin initWithPrimus:self];
    }

    _plugins = [NSDictionary dictionaryWithDictionary:plugins];

    if ([self.transformer respondsToSelector:@selector(onEvent:userInfo:)])
        [self.transformer onEvent:PrimusEventOutgoingOpen
                         userInfo:nil];
}

/**
 * Send a new message.
 *
 * @param data  The data that needs to be written.
 * @returns     Always returns true.
 */
- (BOOL)write:(id)data
{
    if (kPrimusReadyStateOpen != self.readyState) {
        [_buffer addObject:data];

        return YES;
    }

    for (PrimusTransformCallback transform in self.transformers.outgoing) {
        NSMutableDictionary *packet = [@{ @"data": data } mutableCopy];

        if (NO == transform(packet)) {
            // When false is returned by an incoming transformer it means that's
            // being handled by the transformer and we should not emit the `data`
            // event.

            return NO;
        }

        data = packet[@"data"];
    }

    NSDictionary *wrappedData = @{
                                  @"data": data,
                                  @"type": @(PrimusEventPublishTypeEvent)
                                  };
    
    bool isPrimusEvent = [data isKindOfClass:[NSString class]] && [data hasPrefix:@"primus::"];


    [self.parser encode:(isPrimusEvent ? data : wrappedData) callback:^(NSError *error, id data) {
        if (![self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            return;

        if (error) {
            return [self.primusDelegate onEvent:PrimusEventError userInfo:@{
                                                                            @"error": error
                                                                            }];
        }

        [self.transformer onEvent:PrimusEventOutgoingData
                         userInfo:@{
                                    @"data": data
                                    }];
    }];

    return YES;
}

/**
 * Retrieve the current id from the server.
 *
 * @param fn Callback function.
 */
- (void)id:(PrimusIdCallback)fn
{
    if (self.transformer && [self.transformer respondsToSelector:@selector(id)]) {
        return fn(self.transformer.id);
    }

    [self write:@"primus::id::"];

    [self once:@"incoming::id" listener:fn];
}

/**
 * Send a new heartbeat over the connection to ensure that we're still
 * connected and our internet connection didn't drop. We cannot use server side
 * heartbeats for this unfortunately.
 */
- (void)heartbeat
{
    if (! self.options.ping) {
        return;
    }

    __block id pong = ^{
        [_timers.pong invalidate];
        _timers.pong = nil;

        if (!self.online) {
            return;
        }

        _online = NO;

        if (![self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            return;
        [self.primusDelegate onEvent:PrimusEventOffline
                            userInfo:nil];
        [self.primusDelegate onEvent:PrimusEventIncomingEnd
                            userInfo:nil];
    };

    __block id ping = ^{
        [_timers.ping invalidate];
        _timers.ping = nil;

        [self write:[NSString stringWithFormat:@"primus::ping::%f", [[NSDate date] timeIntervalSince1970]]];

        if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            [self.primusDelegate onEvent:PrimusEventOutgoingPing
                                userInfo:nil];

        _timers.pong = [NSTimer scheduledTimerWithTimeInterval:self.options.pong block:pong repeats:NO];
    };

    _timers.ping = [NSTimer scheduledTimerWithTimeInterval:self.options.ping block:ping repeats:NO];
}

/**
 * Start a connection timeout.
 */
- (void)timeout
{
    _timers.connect = [NSTimer scheduledTimerWithTimeInterval:self.options.timeout block:^{
        [_timers.connect invalidate];
        _timers.connect = nil;

        if (kPrimusReadyStateOpen == self.readyState) {
            return;
        }

        if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            [self.primusDelegate onEvent:PrimusEventTimeout
                                userInfo:nil];

        if ([self.options.reconnect.strategies containsObject:@(kPrimusReconnectionStrategyTimeout)]) {
            [self reconnect];
        } else {
            [self end];
        }
    } repeats:NO];
}

/**
 * Exponential back off algorithm for retry operations. It uses an randomized
 * retry so we don't DDOS our server when it goes down under pressure.
 *
 * @param callback  Callback to be called after the timeout.
 * @param opts      Options for configuring the timeout.
 */
- (void)backoff:(PrimusReconnectCallback)callback options:(PrimusReconnectOptions *)options
{
    if (options.backoff) {
        return;
    }

    if (options.attempt > options.retries) {
        NSError *error = [NSError errorWithDomain:kPrimusErrorDomain code:kPrimusErrorUnableToRetry userInfo:nil];

        callback(error, options);

        return;
    }

    options.backoff = YES;

    options.timeout = options.attempt != 1
        ? MIN(round((drand48() + 1) * options.minDelay * pow(options.factor, options.attempt)), options.maxDelay)
        : options.minDelay;

    NSMutableDictionary *userInfo = [@{} mutableCopy];

    if (options)
        userInfo[@"options"] = options;

    if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
        [self.primusDelegate onEvent:PrimusEventReconnecting
                            userInfo:userInfo];

    options.timeout = ceilf(options.timeout);

    _timers.reconnect = [NSTimer scheduledTimerWithTimeInterval:options.timeout block:^{
        _timers.reconnect = nil;

        callback(nil, options);

        options.attempt++;
        options.backoff = NO;
    } repeats:NO];
}

- (void)forceReconnect
{
    _timers.reconnect = nil;

    // Try to re-use the existing attempt.
    _attemptOptions = _attemptOptions ?: [_reconnectOptions copy];

    // Try to re-open the connection again.
    if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
        [self.primusDelegate onEvent:PrimusEventReconnect
                            userInfo:@{
                                       @"options": _attemptOptions
                                       }];

    if ([self.transformer respondsToSelector:@selector(onEvent:userInfo:)])
        [self.transformer onEvent:PrimusEventOutgoingReconnect
                         userInfo:nil];


    _attemptOptions.attempt++;
    _attemptOptions.backoff = NO;
}

/**
 * Start a new reconnect procedure.
 */
- (void)reconnect
{
    // Try to re-use the existing attempt.
    _attemptOptions = _attemptOptions ?: [_reconnectOptions copy];

    [self backoff:^(NSError *error, PrimusReconnectOptions *options) {
        if (error) {
            _attemptOptions = nil;

            if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
                [self.primusDelegate onEvent:PrimusEventEnd
                                    userInfo:nil];

            return;
        }

        // Try to re-open the connection again.
        if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            [self.primusDelegate onEvent:PrimusEventReconnect
                                userInfo:@{
                                           @"options": options
                                           }];

        if ([self.transformer respondsToSelector:@selector(onEvent:userInfo:)])
            [self.transformer onEvent:PrimusEventOutgoingReconnect
                                userInfo:nil];
    } options:_attemptOptions];
}

/**
 * Close the connection.
 */
- (void)end
{
    [self end:nil];
}

/**
 * Close the connection.
 *
 * @param data  The last packet of data.
 */
- (void)end:(id)data
{
    if (kPrimusReadyStateClosed == self.readyState && !_timers.connect) {
        return;
    }

    if (data) {
        [self write:data];
    }

    _writable = NO;
    _readyState = kPrimusReadyStateClosed;

    [_timers clearAll];

    if ([self.transformer respondsToSelector:@selector(onEvent:userInfo:)])
        [self.transformer onEvent:PrimusEventOutgoingEnd
                         userInfo:nil];
    if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)]) {
        [self.primusDelegate onEvent:PrimusEventClose
                            userInfo:nil];
        [self.primusDelegate onEvent:PrimusEventEnd
                            userInfo:nil];
    }
}

/**
 * Register a new message transformer. This allows you to easily manipulate incoming
 * and outgoing data which is particularity handy for plugins that want to send
 * meta data together with the messages.
 *
 * @param type  Incoming or outgoing
 * @param fn    A new message transformer.
 */
- (void)transform:(NSString *)type fn:(PrimusTransformCallback)fn
{
    if ([type isEqualToString:@"incoming"]) {
        [self.transformers.incoming addObject:fn];

        return;
    }

    if ([type isEqualToString:@"outgoing"]) {
        [self.transformers.outgoing addObject:fn];

        return;
    }
}

- (void)onEvent:(NSString *)event userInfo:(NSDictionary *)userInfo
{
    if ([event isEqualToString:PrimusEventOutgoingOpen]) {
        _readyState = kPrimusReadyStateOpening;
        [self timeout];
    } else if ([event isEqualToString:PrimusEventOutgoingReconnect]) {
        [self timeout];
    } else if ([event isEqualToString:PrimusEventIncomingOpen]) {
        _readyState = kPrimusReadyStateOpen;

        _attemptOptions = nil;

        [_timers.ping invalidate];
        _timers.ping = nil;

        [_timers.pong invalidate];
        _timers.pong = nil;

        if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            [self.primusDelegate onEvent:PrimusEventOpen
                                userInfo:nil];

        [self heartbeat];

        if (_buffer.count > 0) {
            for (id data in _buffer) {
                [self write:data];
            }

            [_buffer removeAllObjects];
        }
    } else if ([event isEqualToString:PrimusEventIncomingPong]) {
        __unused NSNumber *time = userInfo[@"time"];

        _online = YES;

        [_timers.pong invalidate];
        _timers.pong = nil;

        [self heartbeat];
    } else if ([event isEqualToString:PrimusEventIncomingError]) {
        NSError *error = userInfo[@"error"];

        [self.primusDelegate onEvent:PrimusEventError
                            userInfo:@{
                                       @"error": error
                                       }];

        if (_attemptOptions.attempt) {
            return [self reconnect];
        }

        if (_timers.connect) {
            if ([self.options.reconnect.strategies containsObject:@(kPrimusReconnectionStrategyTimeout)]) {
                [self reconnect];
            } else {
                [self end];
            }
        }
    } else if ([event isEqualToString:PrimusEventIncomingData]) {
        id raw = userInfo[@"raw"];

        [self.parser decode:raw callback:^(NSError *error, id data) {
            if (error) {
                if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
                    [self.primusDelegate onEvent:PrimusEventError
                                        userInfo:@{
                                                   @"error": error
                                                   }];
                return;
            }

            if ([data isKindOfClass:[NSString class]]) {
                if ([data isEqualToString:@"primus::server::close"]) {
                    return [self end];
                }

                if ([data hasPrefix:@"primus::pong::"]) {
                    NSMutableDictionary *userInfo = [@{} mutableCopy];

                    if (data)
                        userInfo[@"time"] = [data substringFromIndex:14];

                    return [self onEvent:PrimusEventIncomingPong
                                userInfo:userInfo];
                }

                if ([data hasPrefix:@"primus::id::"]) {
                    return [self emit:@"incoming::id", [data substringFromIndex:12]];
                }
            }

            for (PrimusTransformCallback transform in self.transformers.incoming) {
                NSMutableDictionary *packet = [@{ @"data": data } mutableCopy];

                if (NO == transform(packet)) {
                    // When false is returned by an incoming transformer it means that's
                    // being handled by the transformer and we should not emit the `data`
                    // event.

                    return;
                }

                data = packet[@"data"];
            }

            NSMutableDictionary *userInfo = [@{} mutableCopy];
            if (data)
                userInfo[@"data"] = data;
            if (raw)
                userInfo[@"raw"] = raw;

            if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
                [self.primusDelegate onEvent:PrimusEventData
                                    userInfo:userInfo];
        }];
    } else if ([event isEqualToString:PrimusEventIncomingEnd]) {
        NSString *intentional = userInfo[@"intentional"];

        PrimusReadyState readyState = self.readyState;

        _readyState = kPrimusReadyStateClosed;

        if (kPrimusReadyStateOpen != readyState) {
            return;
        }

        [_timers clearAll];

        if ([intentional isEqualToString:@"primus::server::close"]) {
            if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
                [self.primusDelegate onEvent:PrimusEventEnd
                                    userInfo:nil];
            return;
        }

        if ([self.primusDelegate respondsToSelector:@selector(onEvent:userInfo:)])
            [self.primusDelegate onEvent:PrimusEventClose
                                userInfo:nil];

        if ([self.options.reconnect.strategies containsObject:@(kPrimusReconnectionStrategyDisconnect)]) {
            [self reconnect];
        }
    }
}

@end
