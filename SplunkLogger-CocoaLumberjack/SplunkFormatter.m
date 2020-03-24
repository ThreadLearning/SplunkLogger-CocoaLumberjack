//
// Created by Mats Melke on 2014-02-18.
//

#import "SplunkFormatter.h"
#import "SplunkFields.h"
#define kSplunkFormatStringWhenLogMsgIsNotJson @"{\"loglevel\":\"%@\",\"timestamp\":\"%@\",\"file\":\"%@\",\"fileandlinenumber\":\"%@:%lu\",\"jsonerror\":\"JSON Output Error when trying to create Splunk JSON\",\"rawlogmessage\":\"%@\"}"

#pragma mark NSMutableDictionary category.
// Defined here so it doesn't spill over to the client projects.
@interface NSMutableDictionary (NilSafe)
- (void)setObjectNilSafe:(id)obj forKey:(id)aKey;
@end

@implementation NSMutableDictionary (NilSafe)
- (void)setObjectNilSafe:(id)obj forKey:(id)aKey {
    // skip nils and NSNull
    if(obj == nil || obj == [NSNull null]) {
        return;
    }
    // skip empty string
    if([obj isKindOfClass: NSString.class] && [obj length]==0) {
        return;
    }
    // The object is fine, insert it
    [self setObject:obj forKey:aKey];
}
@end



@implementation SplunkFormatter {
    id<SplunkFieldsDelegate> splunkFieldsDelegate;
}

- (id)init {
    if((self = [super init]))
    {
        // Use standard SplunkFields Delegate
        splunkFieldsDelegate = [[SplunkFields alloc] init];
        self.alwaysIncludeRawMessage = YES;
    }
    return self;
}

- (id)initWithSplunkFieldsDelegate:(id<SplunkFieldsDelegate>)delegate {
    if((self = [super init]))
    {
        splunkFieldsDelegate = delegate;
        self.alwaysIncludeRawMessage = YES;
    }
    return self;
}

- (NSDictionary *)formatLogMessage:(DDLogMessage *)logMessage
{
    // Get the fields that should be included in every log entry.
    NSMutableDictionary *logfields = [NSMutableDictionary dictionaryWithDictionary:[splunkFieldsDelegate splunkFieldsToIncludeInEveryLogStatement]];

    NSString *logLevel;
    switch (logMessage->_flag)
    {
        case DDLogFlagError : logLevel = @"error"; break;
        case DDLogFlagWarning  : logLevel = @"warning"; break;
        case DDLogFlagInfo  : logLevel = @"info"; break;
        case DDLogFlagDebug : logLevel = @"debug"; break;
        default             : logLevel = @"verbose"; break;
    }
    [logfields setObjectNilSafe:logLevel forKey:@"loglevel"];

    NSString *iso8601DateString = [self iso8601StringFromDate:(logMessage->_timestamp)];
    [logfields setObjectNilSafe:iso8601DateString forKey:@"timestamp"];

    NSString *filestring = [self lastPartOfFullFilePath:[NSString stringWithFormat:@"%@", logMessage->_file]];
    [logfields setObjectNilSafe:filestring forKey:@"file"];
    [logfields setObjectNilSafe:[NSString stringWithFormat:@"%@:%lu", filestring, (unsigned long)logMessage->_line] forKey:@"fileandlinenumber"];

    // newlines are not allowed in POSTS to Splunk
    NSString *logMsg = [logMessage->_message stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    [logfields setObjectNilSafe:logMsg forKey:@"rawlogmessage"];

    NSData *jsondata = [logMsg dataUsingEncoding:NSUTF8StringEncoding];
    NSError *inputJsonError;
    id mostOftenADict = [NSJSONSerialization JSONObjectWithData:jsondata options:NSJSONReadingAllowFragments error:&inputJsonError];
    if ([mostOftenADict isKindOfClass:[NSDictionary class]]) {
        NSDictionary *jsondictForLogMsg = (NSDictionary *)mostOftenADict;
        if (!inputJsonError && [jsondictForLogMsg count] > 0) {
            [logfields addEntriesFromDictionary:jsondictForLogMsg];
            if (!self.alwaysIncludeRawMessage) {
                [logfields removeObjectForKey:@"rawlogmessage"];
            }
        }
    }

    return @{@"event": logfields};
}

#pragma mark Private methods

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    struct tm *timeinfo;
    char buffer[80];

    NSTimeInterval timeInterval = [date timeIntervalSince1970];
    time_t rawtime = (time_t)timeInterval;
    timeinfo = gmtime(&rawtime);
    
    // utc time format with milliseconds
    NSMutableString *format = [NSMutableString stringWithString:@"%Y-%m-%dT%H:%M:%S"];
    [format appendString:[[NSString stringWithFormat:@"%.3lfZ", timeInterval - rawtime] substringFromIndex:1]];
    strftime(buffer, 80, [format cStringUsingEncoding:NSUTF8StringEncoding], timeinfo);

    return [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
}

- (NSString *)lastPartOfFullFilePath:(NSString *)fullfilepath {
    NSString *retvalue;
    NSArray *parts = [fullfilepath componentsSeparatedByString:@"/"];
    if ([parts count] > 0) {
        retvalue = [parts lastObject];
    }
    if ([retvalue length] == 0) {
        retvalue = @"No file";
    }
    return retvalue;
}

@end
