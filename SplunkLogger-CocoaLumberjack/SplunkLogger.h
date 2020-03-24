//
// Created by Mats Melke on 2014-02-20.
//

#import <Foundation/Foundation.h>
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDAbstractDatabaseLogger.h>


@interface SplunkLogger : DDAbstractDatabaseLogger

/// NSString used in stringWithFormat when creating the splunk bulk post url. Must contain placeholders for Splunk API key and Splunk tags
@property (nonatomic, strong) NSString *splunkUrlTemplate;
/// The Splunk API tenant
@property (nonatomic, strong) NSString *splunkTenant;
/// The Splunk API key
@property (nonatomic, strong) NSString *splunkKey;

@property(nonatomic, assign) BOOL outputFirstResponse;

@end
