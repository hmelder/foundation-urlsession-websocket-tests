#pragma once

#import <Foundation/NSURL.h>

// Conformance tests

void testPingPong(NSURL *webSocketURL);
void testSendAndReceiveStringMessage(NSURL *webSocketURL);
void testCloseConnection(NSURL *webSocketURL);
void testTaskStateTransitions(NSURL *webSocketURL);
void testMultipleSequentialReceives(NSURL *webSocketURL);
void testRemoteClosure(NSURL *webSocketURL);
void testMaximumMessageSize(NSURL *webSocketURL);

// Stress tests

/**
 * Upload a large file and download it again from the server.
 */
void testStressLargeFileUpload(NSURL *webSocketURL);
