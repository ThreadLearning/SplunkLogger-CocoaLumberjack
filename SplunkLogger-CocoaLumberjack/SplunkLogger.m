//
// Created by Mats Melke on 2014-02-20.
//

#import "SplunkLogger.h"

@interface NSArray (Map)

- (NSArray *)mapObjectsUsingBlock:(id (^)(id obj, NSUInteger idx))block;

@end

@implementation NSArray (Map)

- (NSArray *)mapObjectsUsingBlock:(id (^)(id obj, NSUInteger idx))block {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[self count]];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [result addObject:block(obj, idx)];
    }];
    return result;
}

@end

@implementation SplunkLogger {
    // Some private iVars
    NSMutableArray *_logMessagesArray;
    NSURL *_splunkURL;
    NSURLSessionConfiguration *_sessionConfiguration;
    BOOL _hasLoggedFirstSplunkPost;
}

- (id)init {
    self = [super init];
    if (self) {
        
        self.outputFirstResponse = YES;
        self.deleteInterval = 0;
        self.maxAge = 0;
        self.deleteOnEverySave = NO;
        self.saveInterval = 600;
        self.saveThreshold = 1000;

        // Make sure we POST the logs when the application is suspended
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(saveOnSuspend)
                                                     name:@"UIApplicationWillResignActiveNotification"
                                                   object:nil];

        // No NSLOG of first Splunk request at all if not DEBUG
        _hasLoggedFirstSplunkPost = YES;
#ifdef DEBUG
        _hasLoggedFirstSplunkPost = NO;
#endif
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark Overridden methods from DDAbstractDatabaseLogger

- (BOOL)db_log:(DDLogMessage *)logMessage
{
    // Return YES if an item was added to the buffer.
    // Return NO if the logMessage was ignored.
    if (!self->_logFormatter) {
        // No formatter set, don't log
#ifdef DEBUG
        NSLog(@"No formatter set in SplunkLogger. Will not log anything.");
#endif
        return NO;
    }
    
    // Initialize the log messages array if we havn't already (or its recently been cleared by saving to splunk).
    if ( ! _logMessagesArray) {
        _logMessagesArray = [NSMutableArray arrayWithCapacity:1000];
    }

    if ([_logMessagesArray count] > 2000) {
        // Too much logging is coming in too fast. Let's not put this message in the array
        // However, we want the abstract logger to retry at some time later, so
        // let's return YES, so the log message counters in the abstract logger keeps getting incremented.
        return YES;
    }

    [_logMessagesArray addObject:[self->_logFormatter formatLogMessage:logMessage]];
    return YES;
}

- (void)db_save
{
    [self db_saveAndDelete];
}

- (void)db_delete
{
    // We don't ever want to delete log messages on Splunk
}

- (void)db_saveAndDelete
{
    if ( ! [self isOnInternalLoggerQueue]) {
        NSAssert(NO, @"db_saveAndDelete should only be executed on the internalLoggerQueue thread, if you're seeing this, your doing it wrong.");
    }
    
    // If no log messages in array, just return
    if ([_logMessagesArray count] == 0) {
        return;
    }

    // Get reference to log messages
    NSArray *oldLogMessagesArray = [_logMessagesArray copy];

    // reset array
    _logMessagesArray = [NSMutableArray arrayWithCapacity:0];

    // Post string to Splunk
    [self doPostToSplunk:oldLogMessagesArray];

}

- (void)doPostToSplunk:(NSArray *)messages {

    if ([messages count] == 0) {
        return;
    }

    if (!self.splunkKey) {
        NSAssert(false, @"You MUST set a splunk api key in the splunkKey property of this logger");
    }

    if (!_splunkURL) {
        _splunkURL = [NSURL URLWithString:[NSString stringWithFormat:self.splunkUrlTemplate, self.splunkTenant]];
    }

    if (!_sessionConfiguration) {
        _sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _sessionConfiguration.HTTPAdditionalHeaders = @{
                @"Authorization"  : [NSString stringWithFormat:@"Splunk %@", self.splunkKey],
                @"Content-Type"   : @"application/json"
        };
        _sessionConfiguration.allowsCellularAccess = YES;
    }

    if (!_hasLoggedFirstSplunkPost && _outputFirstResponse) {
        NSLog(@"Posting to Splunk: %@", messages);
    }

    NSURLSession *session = [NSURLSession sessionWithConfiguration:_sessionConfiguration delegate:self delegateQueue:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_splunkURL];
    [request setHTTPMethod:@"POST"];

    // Batch events should be stacked instead of placed in JSON array
    NSArray *jsonMessages = [messages mapObjectsUsingBlock:^(id message, NSUInteger idx) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }];

    NSLog(@"Body: %@", [jsonMessages componentsJoinedByString:@"\n"]);
    [request setHTTPBody:[[jsonMessages componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    NSURLSessionDataTask *postDataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!_hasLoggedFirstSplunkPost) {
            _hasLoggedFirstSplunkPost = YES;
            if (error) {
                NSLog(@"SPLUNK ERROR: Error object = %@. This was the last NSLog statement you will see from SplunkLogger. The rest of the posts to Splunk will be done silently",error);
            } else if (data && _outputFirstResponse) {
                NSString *responseString = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"SPLUNK: Response = %@  This was the last NSLog statement you will see from SplunkLogger. The rest of the posts to Splunk will be done silently.",responseString);
            }
        }
    }];
    [postDataTask resume];
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler{
  if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]){
    if([challenge.protectionSpace.host isEqualToString:[_splunkURL host]]){
      NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
      completionHandler(NSURLSessionAuthChallengeUseCredential,credential);
    }
  }
}

#pragma mark Property getters

- (NSString *)splunkUrlTemplate {
    if (!_splunkUrlTemplate) {
        // Change to the correct url for bulk posting log entries in Splunk
        _splunkUrlTemplate = @"https://my-splunk-server.dev:8088/services/collector";
    }
    return _splunkUrlTemplate;
}

- (void) saveOnSuspend {
#ifdef DEBUG
    NSLog(@"Suspending, posting logs to Splunk");
#endif
    
    dispatch_async(_loggerQueue, ^{
        [self db_save];
    });
}

@end
