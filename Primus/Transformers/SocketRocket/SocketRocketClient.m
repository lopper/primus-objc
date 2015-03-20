//
//  SocketRocketClient.m
//  Primus
//
//  Created by Nuno Sousa on 17/01/14.
//  Copyright (c) 2014 Seegno. All rights reserved.
//

#if __has_include(<SocketRocket/SRWebSocket.h>)

#import "SocketRocketClient.h"

typedef NS_ENUM(NSInteger, SocketRocketErrorCode) {
    kSocketRocketErrorCode = 1000,
    kSocketRocketErrorCodeNormal = 1000,
    kSocketRocketErrorCodeGoingAway = 1001,
    kSocketRocketErrorCodeProtocolError = 1002,
    kSocketRocketErrorCodeUnsupportedData = 1003,
    kSocketRocketErrorCodeReserved = 1004,
    kSocketRocketErrorCodeReservedForExtensions = 1005,
    kSocketRocketErrorCodeReservedForExtensions2 = 1006,
    kSocketRocketErrorCodeInconsistentOrInvalidData = 1007,
    kSocketRocketErrorCodePolicyViolation = 1008,
    kSocketRocketErrorCodeMessageTooBig = 1009,
    kSocketRocketErrorCodeExtensionHandshakeMissing = 1010,
    kSocketRocketErrorCodeAnUnexpectedConditionPreventedTheRequestFromBeingFulfilled = 1011
};

@implementation SocketRocketClient

- (id)initWithPrimus:(id<PrimusProtocol>)primus
{
    self = [super initWithPrimus:primus];

    if (self) {
        [self bindEvents];
    }

    return self;
}

- (void)bindEvents
{
    [_primus on:@"outgoing::open" listener:^{
        @try {
            _socket = [[SocketRocketWebSocket alloc] initWithURLRequest:_primus.request];

            _socket.delegate = self;
            _socket.stayConnectedInBackground = _primus.options.stayConnectedInBackground;

            [_socket open];
        }
        @catch (NSException *exception) {
            [_primus emit:@"incoming::error", exception];
        }
    }];

    [_primus on:@"outgoing::data" listener:^(id data) {
        if (!_socket || SR_OPEN != _socket.readyState) {
            return;
        }

        @try {
            [_socket send:data];
        }
        @catch (NSException *exception) {
            [_primus emit:@"incoming::error", exception];
        }
    }];

    [_primus on:@"outgoing::reconnect" listener:^{
        if (_socket) {
            [_primus emit:@"outgoing::end"];
        }

        [_primus emit:@"outgoing::open"];
    }];

    [_primus on:@"outgoing::end" listener:^{
        if (! _socket) {
            return;
        }

        [_socket close];
        _socket = nil;
    }];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    [_primus emit:@"incoming::open"];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    [_primus emit:@"incoming::end", reason];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    [_primus emit:@"incoming::data", message];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    [_primus emit:@"incoming::error", error];

    if (_socket.readyState == SR_CLOSED) {
        [_primus emit:@"incoming::end", error.localizedDescription];
    }
}

- (void)setStayConnectedInBackground:(BOOL)stayConnectedInBackground
{
    _primus.options.stayConnectedInBackground = stayConnectedInBackground;
    _socket.stayConnectedInBackground = stayConnectedInBackground;
}

@end

#endif
