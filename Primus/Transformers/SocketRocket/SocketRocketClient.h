//
//  SocketRocketClient.h
//  Primus
//
//  Created by Nuno Sousa on 17/01/14.
//  Copyright (c) 2014 Seegno. All rights reserved.
//



#import "SocketRocketWebSocket.h"

#import "Transformer.h"

@interface SocketRocketClient : Transformer<FP_SRWebSocketDelegate>
{
    FP_SocketRocketWebSocket *_socket;
}

@end

