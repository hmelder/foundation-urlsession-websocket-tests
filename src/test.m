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