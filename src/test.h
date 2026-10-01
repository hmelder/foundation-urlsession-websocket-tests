#pragma once

#import <Foundation/NSURL.h>

void testPingPong(NSURL *webSocketURL);
void testSendAndReceiveStringMessage(NSURL *webSocketURL);
void testCloseConnection(NSURL *webSocketURL);
void testTaskStateTransitions(NSURL *webSocketURL);
void testMultipleSequentialReceives(NSURL *webSocketURL);
void testRemoteClosure(NSURL *webSocketURL);