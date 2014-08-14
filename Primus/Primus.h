//
//  Primus.h
//  Primus
//
//  Created by Nuno Sousa on 1/8/14.
//  Copyright (c) 2014 Seegno. All rights reserved.
//

#import <Reachability/Reachability.h>
#import <NSTimer-Blocks/NSTimer+Blocks.h>

#import "TransformerProtocol.h"
#import "ParserProtocol.h"
#import "PluginProtocol.h"

#import "PrimusError.h"
#import "PrimusTimers.h"
#import "PrimusTransformers.h"
#import "PrimusProtocol.h"

@interface Primus : NSObject<PrimusProtocol>
{
    NSUInteger _timeout;
    NSMutableArray *_buffer;
    PrimusTimers *_timers;
    Reachability *_reach;
}

@property (nonatomic, readonly) BOOL online;
@property (nonatomic, readonly) BOOL writable;
@property (nonatomic, readonly) PrimusReadyState readyState;
@property (nonatomic, readonly) PrimusConnectOptions *options;
@property (nonatomic, readonly) PrimusReconnectOptions *reconnectOptions;
@property (nonatomic, readonly) PrimusReconnectOptions *attemptOptions;

@property (nonatomic, readonly) PrimusTransformers *transformers;
@property (nonatomic, readonly) NSDictionary *plugins;
@property (nonatomic) id<TransformerProtocol> transformer;
@property (nonatomic) id<ParserProtocol> parser;

- (void)reconnect;

@end
