//
//  UITextField+HYSCat.h
//  VSCAM_Photo_Group_iPhone
//
//  Created by iURCoder on 12/10/15.
//  Copyright © 2015 iUR. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UITextField (HYSCat)

- (void)whenValueChanged:(void (^)(UITextField *sender))block;

@end
