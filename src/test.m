#import <Foundation/Foundation.h>

#define PASS(expr, msg) fprintf(stderr, "%s: %s\n", expr ? "OK" : "FAILED", msg)
#define PASS_WITH_ACTION(expr, msg, action_stmt)                                                   \
	PASS(expr, msg);                                                                               \
	if (expr) {                                                                                    \
		action_stmt;                                                                               \
	}
#define WAIT_FOR_EXPR_MS(expr, duration, msg)                                                      \
	do {                                                                                           \
		struct timespec start, now;                                                                \
		clock_gettime(CLOCK_MONOTONIC, &start);                                                    \
		bool _cond = false;                                                                        \
		while (!(_cond = (expr))) {                                                                \
			clock_gettime(CLOCK_MONOTONIC, &now);                                                  \
			double elapsed_ms =                                                                    \
				(now.tv_sec - start.tv_sec) * 1000.0 + (now.tv_nsec - start.tv_nsec) / 1000000.0;  \
			if (elapsed_ms >= (double) (duration)) {                                               \
				break;                                                                             \
			}                                                                                      \
			struct timespec req = {.tv_sec = 0, .tv_nsec = 1000000}; /* 1ms */                     \
			nanosleep(&req, NULL);                                                                 \
		}                                                                                          \
		PASS(_cond, msg);                                                                          \
	} while (0)

void testPingPong(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;

	_Atomic(int) expectedAsyncTests = 2;
	_Atomic(int) __block finishedAsyncTests = 0;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	PASS(session != nil, "URLSession object was created");
	task = [session webSocketTaskWithURL:webSocketURL];
	PASS(task != nil, "websocket task object was created");

	[task sendPingWithPongReceiveHandler:^(NSError *_Nullable error) {
		PASS(error == nil, "first pong receive handler error is nil");
		finishedAsyncTests += 1;
	}];

	[task sendPingWithPongReceiveHandler:^(NSError *_Nullable error) {
		PASS(error == nil, "second pong receive handler error is nil");
		finishedAsyncTests += 1;
	}];

	[task resume];

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 1000 /* ms */,
					 "all handlers were called");
	[session invalidateAndCancel];
}

void testSendAndReceiveStringMessage(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;
	NSURLSessionWebSocketMessage *webSocketMessage;
	NSString *message;

	_Atomic(int) expectedAsyncTests = 2;
	_Atomic(int) __block finishedAsyncTests = 0;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	PASS(session != nil, "URLSession object was created");
	task = [session webSocketTaskWithURL:webSocketURL];
	PASS(task != nil, "websocket task object was created");

	message = @"Hello there!";
	webSocketMessage = [[NSURLSessionWebSocketMessage alloc] initWithString:message];
	PASS(webSocketMessage != nil, "message object was created");

	[task sendMessage:webSocketMessage
		completionHandler:^(NSError *_Nullable error) {
			PASS(error == nil, "send completion handler error is nil");
			finishedAsyncTests += 1;
		}];

	[task receiveMessageWithCompletionHandler:^(
			  NSURLSessionWebSocketMessage *_Nullable responseMessage, NSError *_Nullable error) {
		PASS(error == nil, "receive completion handler error is nil");
		PASS(responseMessage != nil, "response message is not nil");
		PASS([responseMessage type] == NSURLSessionWebSocketMessageTypeString,
			 "response message is a string");
		PASS([[responseMessage string] isEqualToString:message], "response is correct");
		finishedAsyncTests += 1;
	}];

	[task resume];

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 1000 /* ms */,
					 "all tests succeeded");
	[session invalidateAndCancel];
}

void testCloseConnection(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;

	_Atomic(int) expectedAsyncTests = 1;
	_Atomic(int) __block finishedAsyncTests = 0;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	task = [session webSocketTaskWithURL:webSocketURL];

	[task resume];
	PASS(task.state == NSURLSessionTaskStateRunning, "task is running after resume");

	NSData *closeReason = [@"Client disconnecting" dataUsingEncoding:NSUTF8StringEncoding];
	[task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:closeReason];

	// Attempting to send a message on a closed task should result in an error
	NSURLSessionWebSocketMessage *message =
		[[NSURLSessionWebSocketMessage alloc] initWithString:@"Too late"];
	[task sendMessage:message
		completionHandler:^(NSError *_Nullable error) {
			PASS(error != nil, "sending on a closed/canceled task results in an error");
			finishedAsyncTests += 1;
		}];

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 1000 /* ms */,
					 "close connection tests succeeded");
	[session invalidateAndCancel];
}

void testTaskStateTransitions(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	task = [session webSocketTaskWithURL:webSocketURL];

	PASS(task.state == NSURLSessionTaskStateSuspended, "task starts in suspended state");

	[task resume];
	PASS(task.state == NSURLSessionTaskStateRunning, "task transitions to running state");

	[task suspend];
	PASS(task.state == NSURLSessionTaskStateSuspended, "task transitions back to suspended state");

	[task cancel];
	// PASS(task.state == NSURLSessionTaskStateCanceling
	// 		 || task.state == NSURLSessionTaskStateCanceling,
	// 	 "task transitions to canceled state");
	[session invalidateAndCancel];
}

void testMultipleSequentialReceives(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;

	_Atomic(int) expectedAsyncTests = 4; // 2 sends, 2 receives
	_Atomic(int) __block finishedAsyncTests = 0;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	task = [session webSocketTaskWithURL:webSocketURL];

	NSURLSessionWebSocketMessage *msg1 =
		[[NSURLSessionWebSocketMessage alloc] initWithString:@"Message 1"];
	NSURLSessionWebSocketMessage *msg2 =
		[[NSURLSessionWebSocketMessage alloc] initWithString:@"Message 2"];

	[task sendMessage:msg1
		completionHandler:^(NSError *error) {
			PASS(error == nil, "first send successful");
			finishedAsyncTests += 1;
		}];

	[task sendMessage:msg2
		completionHandler:^(NSError *error) {
			PASS(error == nil, "second send successful");
			finishedAsyncTests += 1;
		}];

	[task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *response1,
												NSError *error1) {
		PASS(error1 == nil && [[response1 string] isEqualToString:@"Message 1"],
			 "first receive successful");
		finishedAsyncTests += 1;

		// Queue second receive only after first one finishes
		[task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *response2,
													NSError *error2) {
			PASS(error2 == nil && [[response2 string] isEqualToString:@"Message 2"],
				 "second receive successful");
			finishedAsyncTests += 1;
		}];
	}];

	[task resume];

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 2000 /* ms */,
					 "multiple sequential sends and receives succeeded");
	[session invalidateAndCancel];
}

void testRemoteClosure(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;
	NSURLSessionWebSocketMessage *webSocketMessage;
	NSString *message;

	_Atomic(int) expectedAsyncTests = 3; // 1x send, 1x receive, 1x ping
	_Atomic(int) __block finishedAsyncTests = 0;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	task = [session webSocketTaskWithURL:webSocketURL];

	// The request and response strings are hard-coded in the python WebSocket server
	message = @"close!";
	webSocketMessage = [[NSURLSessionWebSocketMessage alloc] initWithString:message];

	[task sendMessage:webSocketMessage
		completionHandler:^(NSError *_Nullable error) {
			PASS(error == nil, "sending close request was successful");

			[task receiveMessageWithCompletionHandler:^(
					  NSURLSessionWebSocketMessage *_Nullable responseMessage,
					  NSError *_Nullable responseError) {
				PASS(error == nil, "received response from server without error");
				PASS(responseMessage != nil, "response message is not nil");
				PASS([[responseMessage string] isEqualToString:@"closing!"],
					 "response message is correct");

				// The connection is now closed by the server. An attempt to send a ping shall
				// result in an error.
				[task sendPingWithPongReceiveHandler:^(NSError *_Nullable pingError) {
					PASS(pingError != nil, "ping error is populated");
					finishedAsyncTests += 1;
				}];

				finishedAsyncTests += 1;
			}];

			finishedAsyncTests += 1;
		}];

	[task resume];
	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 2000 /* ms */,
					 "remote connection closure succeeded");
	NSLog(@"task close code %ld", [task closeCode]);
	NSLog(@"task status %ld", [task state]);
	PASS([task closeCode] == NSURLSessionWebSocketCloseCodeNormalClosure,
		 "remote close code is correct");
	PASS([task closeReason] != nil, "close reason is available");
	NSString *closeReasonString = [[NSString alloc] initWithData:[task closeReason]
														encoding:NSUTF8StringEncoding];
	PASS(closeReasonString != nil, "close reason could be decoded into an UTF-8 string");
	PASS([closeReasonString isEqualToString:@"client requested closure"],
		 "close reason is correct");

	[session invalidateAndCancel];
}

void testMaximumMessageSize(NSURL *webSocketURL) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;
	NSURLSessionWebSocketMessage *webSocketMessage;

	_Atomic(int) expectedAsyncTests = 2;
	_Atomic(int) __block finishedAsyncTests = 0;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];
	task = [session webSocketTaskWithURL:webSocketURL];
	webSocketMessage = [[NSURLSessionWebSocketMessage alloc] initWithString:@"hello!"];

	[task setMaximumMessageSize:4];
	[task sendMessage:webSocketMessage
		completionHandler:^(NSError *_Nullable sendError) {
			PASS(sendError == nil, "no error occurred while sending a message");

			[task receiveMessageWithCompletionHandler:^(
					  NSURLSessionWebSocketMessage *_Nullable responseMessage,
					  NSError *_Nullable responseError) {
				PASS(responseError != nil, "response error is not nil");
				finishedAsyncTests += 1;
			}];

			finishedAsyncTests += 1;
		}];

	[task resume];

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 2000 /* ms */,
					 "all handlers called");

	PASS([task state] == NSURLSessionTaskStateCompleted,
		 "overrun in internal buffer results in task completion");
	PASS([task closeCode] == NSURLSessionWebSocketCloseCodeMessageTooBig, "close code is correct");
	[session invalidateAndCancel];
}

void testInvalidURLSchemeHandling(void) {
	NSURLSession *session;
	NSURLSessionConfiguration *configuration;
	NSURLSessionWebSocketTask *task;

	configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
	session = [NSURLSession sessionWithConfiguration:configuration];

	// Test non-WebSocket scheme (e.g. ftp:// or http:// without upgrade expectations)
	NSURL *invalidURL = [NSURL URLWithString:@"ftp://127.0.0.1:8080/ws"];

	// Task creation with non-ws/wss URLs should either return nil or fail during execution
	@try {
		task = [session webSocketTaskWithURL:invalidURL];
	} @catch (...) {
		PASS(task == nil, "task created with non-websocket scheme URL");
	}

	[session invalidateAndCancel];
}

// Delegate implementation to test NSURLSessionWebSocketDelegate callbacks
@interface TestWebSocketDelegate : NSObject <NSURLSessionWebSocketDelegate>
@property (nonatomic, assign) bool didOpen;
@property (nonatomic, assign) bool didClose;
@property (nonatomic, assign) NSURLSessionWebSocketCloseCode closeCode;
@end

@implementation TestWebSocketDelegate

- (void)URLSession:(NSURLSession *)session
		  webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
	didOpenWithProtocol:(NSString *)protocol {
	self.didOpen = true;
}

- (void)URLSession:(NSURLSession *)session
	   webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
	didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode
			  reason:(NSData *)reason {
	self.didClose = true;
	self.closeCode = closeCode;
}

@end

void testWebSocketDelegateCallbacks(NSURL *webSocketURL) {
	TestWebSocketDelegate *delegate = [[TestWebSocketDelegate alloc] init];
	NSURLSessionConfiguration *configuration =
		[NSURLSessionConfiguration defaultSessionConfiguration];

	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration
														  delegate:delegate
													 delegateQueue:nil];

	NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:webSocketURL];
	[task resume];

	// Wait for didOpen delegate callback
	WAIT_FOR_EXPR_MS(delegate.didOpen == true, 1000 /* ms */,
					 "didOpenWithProtocol delegate callback triggered");

	NSData *closeReason = [@"Normal test teardown" dataUsingEncoding:NSUTF8StringEncoding];
	[task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:closeReason];

	// Wait for didClose delegate callback
	WAIT_FOR_EXPR_MS(delegate.didClose == true, 1000 /* ms */,
					 "didCloseWithCode delegate callback triggered");
	PASS(delegate.closeCode == NSURLSessionWebSocketCloseCodeNormalClosure,
		 "close code matches expected normal closure");
	[session invalidateAndCancel];
}

// RFC 6455 Section 5.5: Empty Control & Data Payloads
// Messages and control frames with zero-length payloads must be handled validly without error.
void testRFC6455ZeroLengthPayloads(NSURL *webSocketURL) {
	NSURLSession *session = [NSURLSession
		sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
	NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:webSocketURL];

	_Atomic(int) expectedAsyncTests = 3;
	_Atomic(int) __block finishedAsyncTests = 0;

	// 1. Empty Text Message
	NSURLSessionWebSocketMessage *emptyStringMsg =
		[[NSURLSessionWebSocketMessage alloc] initWithString:@""];
	PASS(emptyStringMsg != nil, "empty string message created");

	// 2. Empty Data Message
	NSURLSessionWebSocketMessage *emptyDataMsg =
		[[NSURLSessionWebSocketMessage alloc] initWithData:[NSData data]];
	PASS(emptyDataMsg != nil, "empty data message created");

	[task sendMessage:emptyStringMsg
		completionHandler:^(NSError *error) {
			PASS(error == nil, "RFC 6455: sent 0-byte text frame successfully");
			finishedAsyncTests += 1;
		}];

	[task sendMessage:emptyDataMsg
		completionHandler:^(NSError *error) {
			PASS(error == nil, "RFC 6455: sent 0-byte binary frame successfully");
			finishedAsyncTests += 1;
		}];

	// 3. Ping with 0-byte payload (sendPingWithPongReceiveHandler handles zero-payload pings)
	[task sendPingWithPongReceiveHandler:^(NSError *_Nullable error) {
		PASS(error == nil, "RFC 6455: empty ping received corresponding pong");
		finishedAsyncTests += 1;
	}];

	[task resume];

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 1000 /* ms */,
					 "RFC 6455 zero-length payload test completed");

	[session invalidateAndCancel];
}

// RFC 6455 Section 5.5.1: Close Frame Reason Payload Limit
// Control frame payload MUST NOT exceed 125 bytes. Since close code takes 2 bytes,
// the reason payload string/data length MUST NOT exceed 123 bytes.
void testRFC6455CloseReasonPayloadLimit(NSURL *webSocketURL) {
	NSURLSession *session = [NSURLSession
		sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
	NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:webSocketURL];

	_Atomic(int) expectedAsyncTests = 1;
	_Atomic(int) __block finishedAsyncTests = 0;

	// Trigger connection
	[task sendPingWithPongReceiveHandler:^(NSError *_Nullable error) {
		// Generate 124-byte reason (1 byte beyond the 123-byte control payload limit)
		NSMutableString *oversizedReasonStr = [NSMutableString string];
		for (int i = 0; i < 124; i++) {
			[oversizedReasonStr appendString:@"A"];
		}
		NSData *oversizedReason = [oversizedReasonStr dataUsingEncoding:NSUTF8StringEncoding];
		// Canceling with >123 bytes reason should safely truncate or fail gracefully without
		// crashing
		[task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure
						   reason:oversizedReason];

		finishedAsyncTests += 1;
	}];

	[task resume];

	PASS(task.state == NSURLSessionTaskStateCanceling
			 || task.state == NSURLSessionTaskStateCompleted,
		 "RFC 6455: close frame handled oversized close reason safely");

	WAIT_FOR_EXPR_MS(expectedAsyncTests == finishedAsyncTests, 1000 /* ms */,
					 "RFC 6455 close reason payload limit test completed");

	[session invalidateAndCancel];
}