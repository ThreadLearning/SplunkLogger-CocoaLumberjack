//
// Created by Mats Melke on 2014-02-20.
//

#import <Foundation/Foundation.h>
#import "SplunkFormatter.h"

@interface SplunkFields : NSObject <SplunkFieldsDelegate>
@property (strong, nonatomic) NSString *appversion;
@property (strong, nonatomic) NSString *userid;
@property (strong, nonatomic) NSString *sessionid;
@end
