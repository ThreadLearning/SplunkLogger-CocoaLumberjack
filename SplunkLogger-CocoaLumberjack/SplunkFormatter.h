//
// Created by Mats Melke on 2014-02-18.
//

#import <Foundation/Foundation.h>
#import <CocoaLumberjack/CocoaLumberjack.h>


@protocol SplunkFieldsDelegate
- (NSDictionary *)splunkFieldsToIncludeInEveryLogStatement;
@end

@interface SplunkFormatter : NSObject <DDLogFormatter>
@property (nonatomic, assign) BOOL alwaysIncludeRawMessage;
- (id)initWithSplunkFieldsDelegate:(id<SplunkFieldsDelegate>)delegate;
@end
