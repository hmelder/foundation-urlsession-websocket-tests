#import <Foundation/Foundation.h>
#include <time.h>

#import "test.h"

@interface TestProgram : NSObject {
	BOOL _shouldExit;
	NSTask *_serverTask;
	NSURL *_webSocketURL;
}
- (instancetype)initWithServerTask:(NSTask *)serverTask URL:(NSURL *)url;
- (void)run;
- (void)indicateTermination;
@end

@implementation TestProgram {
}

- (instancetype)initWithServerTask:(NSTask *)serverTask URL:(NSURL *)url {
	self = [super init];
	if (self) {
		_serverTask = serverTask;
		_webSocketURL = url;
	}
	return self;
}

- (void)indicateTermination {
	_shouldExit = YES;
}

- (void)run {
	testPingPong(_webSocketURL);
	testSendAndReceiveStringMessage(_webSocketURL);
	testCloseConnection(_webSocketURL);
	testTaskStateTransitions(_webSocketURL);
	testMultipleSequentialReceives(_webSocketURL);
	testRemoteClosure(_webSocketURL);
	testMaximumMessageSize(_webSocketURL);
	testInvalidURLSchemeHandling();
	testWebSocketDelegateCallbacks(_webSocketURL);
	testRFC6455ZeroLengthPayloads(_webSocketURL);
	testRFC6455CloseReasonPayloadLimit(_webSocketURL);

	[self atExit];
}

- (void)atExit {
	[_serverTask interrupt];
	[_serverTask waitUntilExit];
	NSLog(@"bye!");
}
@end

// global program singleton
TestProgram *program;

static void signal_handler(int sig) {
	if (sig == SIGINT) {
		[program indicateTermination];
	}
}

static BOOL registerSignalHandler(void) {
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = signal_handler;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = 0;

	if (sigaction(SIGINT, &sa, NULL) < 0) {
		perror("sigaction");
		return NO;
	}

	return YES;
}

static NSTask *createServerTask(int argc, const char *argv[], NSURL *url) {
	NSString *pythonPath;
	NSString *scriptPath;
	NSURL *pythonFileUrl;
	NSURL *scriptFileUrl;
	NSFileManager *fileManager;
	NSTask *serverTask;
	NSError *error = nil;

	pythonPath = [NSString stringWithCString:argv[1] encoding:NSUTF8StringEncoding];
	scriptPath = [NSString stringWithCString:argv[2] encoding:NSUTF8StringEncoding];
	pythonFileUrl = [NSURL fileURLWithPath:pythonPath];
	scriptFileUrl = [NSURL fileURLWithPath:scriptPath];
	fileManager = [NSFileManager defaultManager];

	if (NO == [fileManager fileExistsAtPath:[pythonFileUrl path]]) {
		fprintf(stderr, "no file exists at path '%s'", [[pythonFileUrl path] UTF8String]);
		return nil;
	}
	if (NO == [fileManager fileExistsAtPath:[scriptFileUrl path]]) {
		fprintf(stderr, "no file exists at path '%s'", [[scriptFileUrl path] UTF8String]);
		return nil;
	}

	// Create environment

	NSPipe *outputPipe = [NSPipe pipe];
	NSPipe *errorPipe = [NSPipe pipe];
	NSPipe *inputPipe = [NSPipe pipe];

	[serverTask setStandardOutput:outputPipe];
	[serverTask setStandardError:errorPipe];
	[serverTask setStandardInput:inputPipe]; // Prevents stdin initialization crashes

	serverTask =
		[NSTask launchedTaskWithExecutableURL:pythonFileUrl
									arguments:@[
										[scriptFileUrl path], [url host], [[url port] stringValue]
									]
										error:&error
						   terminationHandler:^(NSTask *_Nonnull task) {
							   NSLog(@"server task %@ terminated", task);
						   }];
	return serverTask;
}

int main(int argc, const char *argv[]) {
	if (argc != 4) {
		fprintf(stderr,
				"please provide the path to the python binary, script, and the WebSocket URL");
		return EXIT_FAILURE;
	}

	@autoreleasepool {
		NSString *webSocketRawURL;
		NSURL *webSocketURL;
		webSocketRawURL = [NSString stringWithCString:argv[3] encoding:NSUTF8StringEncoding];
		webSocketURL = [NSURL URLWithString:webSocketRawURL];

		if (NO == [[webSocketURL scheme] isEqualToString:@"ws"]) {
			fprintf(stderr, "parsed URL scheme is not 'ws'");
			return EXIT_FAILURE;
		}

		NSTask *serverTask = createServerTask(argc, argv, webSocketURL);
		if (!serverTask) {
			return EXIT_FAILURE;
		}

		NSLog(@"server task with pid %d", [serverTask processIdentifier]);

		program = [[TestProgram alloc] initWithServerTask:serverTask URL:webSocketURL];
		if (!registerSignalHandler()) {
			return EXIT_FAILURE;
		}

		sleep(2);

		[program run];
	}
	return 0;
}