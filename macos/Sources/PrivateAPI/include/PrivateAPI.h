#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef int CGSConnectionID;

extern CGSConnectionID CGSMainConnectionID(void);
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection) CF_RETURNS_RETAINED;

NS_ASSUME_NONNULL_END
