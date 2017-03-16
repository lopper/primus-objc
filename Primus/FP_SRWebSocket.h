//
//   Copyright 2012 Square Inc.
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
//

#import <Foundation/Foundation.h>
#import <Security/SecCertificate.h>

typedef NS_ENUM(NSInteger, FP_SRReadyState) {
    FP_SR_CONNECTING   = 0,
    FP_SR_OPEN         = 1,
    FP_SR_CLOSING      = 2,
    FP_SR_CLOSED       = 3,
};

typedef enum FP_SRStatusCode : NSInteger {
    FP_SRStatusCodeNormal = 1000,
    FP_SRStatusCodeGoingAway = 1001,
    FP_SRStatusCodeProtocolError = 1002,
    FP_SRStatusCodeUnhandledType = 1003,
    // 1004 reserved.
    FP_SRStatusNoStatusReceived = 1005,
    // 1004-1006 reserved.
    FP_SRStatusCodeInvalidUTF8 = 1007,
    FP_SRStatusCodePolicyViolated = 1008,
    FP_SRStatusCodeMessageTooBig = 1009,
} FP_SRStatusCode;

@class FP_SRWebSocket;

extern NSString *const FP_SRWebSocketErrorDomain;
extern NSString *const SRHTTPResponseErrorKey;

#pragma mark - FP_SRWebSocketDelegate

@protocol FP_SRWebSocketDelegate;

#pragma mark - FP_SRWebSocket

@interface FP_SRWebSocket : NSObject <NSStreamDelegate>

@property (nonatomic, weak) id <FP_SRWebSocketDelegate> delegate;

@property (nonatomic, readonly) FP_SRReadyState readyState;
@property (nonatomic, readonly, retain) NSURL *url;

@property (nonatomic, readonly) CFHTTPMessageRef receivedHTTPHeaders;

// Optional array of cookies (NSHTTPCookie objects) to apply to the connections
@property (nonatomic, readwrite) NSArray * requestCookies;

// This returns the negotiated protocol.
// It will be nil until after the handshake completes.
@property (nonatomic, readonly, copy) NSString *protocol;

// Protocols should be an array of strings that turn into Sec-WebSocket-Protocol.
- (id)initWithURLRequest:(NSURLRequest *)request protocols:(NSArray *)protocols;
- (id)initWithURLRequest:(NSURLRequest *)request;

// Some helper constructors.
- (id)initWithURL:(NSURL *)url protocols:(NSArray *)protocols;
- (id)initWithURL:(NSURL *)url;

// Delegate queue will be dispatch_main_queue by default.
// You cannot set both OperationQueue and dispatch_queue.
- (void)setDelegateOperationQueue:(NSOperationQueue*) queue;
- (void)setDelegateDispatchQueue:(dispatch_queue_t) queue;

// By default, it will schedule itself on +[NSRunLoop SR_networkRunLoop] using defaultModes.
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)unscheduleFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

// FP_SRWebSockets are intended for one-time-use only.  Open should be called once and only once.
- (void)open;

- (void)close;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

// Send a UTF8 String or Data.
- (void)send:(id)data;

// Send Data (can be nil) in a ping message.
- (void)sendPing:(NSData *)data;

@end

#pragma mark - FP_SRWebSocketDelegate

@protocol FP_SRWebSocketDelegate <NSObject>

// message will either be an NSString if the server is using text
// or NSData if the server is using binary.
- (void)webSocket:(FP_SRWebSocket *)webSocket didReceiveMessage:(id)message;

@optional

- (void)webSocketDidOpen:(FP_SRWebSocket *)webSocket;
- (void)webSocket:(FP_SRWebSocket *)webSocket didFailWithError:(NSError *)error;
- (void)webSocket:(FP_SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
- (void)webSocket:(FP_SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload;

@end

#pragma mark - NSURLRequest (CertificateAdditions)

@interface NSURLRequest (CertificateAdditions)

@property (nonatomic, retain, readonly) NSArray *SR_SSLPinnedCertificates;

@end

#pragma mark - NSMutableURLRequest (CertificateAdditions)

@interface NSMutableURLRequest (CertificateAdditions)

@property (nonatomic, retain) NSArray *SR_SSLPinnedCertificates;

@end

#pragma mark - NSRunLoop (FP_SRWebSocket)

@interface NSRunLoop (FP_SRWebSocket)

+ (NSRunLoop *)SR_networkRunLoop;

@end
