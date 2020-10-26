//
//  SocketRocketWebSocket.h
//  Primus
//
//  Created by Nuno Sousa on 13/03/14.
//  Copyright (c) 2014 Seegno. All rights reserved.
//

#if __has_include(<FPSocketRocket/SRWebSocket.h>)

#import <FPSocketRocket/SRWebSocket.h>

@interface SocketRocketWebSocket : SRWebSocket

@property (nonatomic) BOOL stayConnectedInBackground;

@end

#endif
