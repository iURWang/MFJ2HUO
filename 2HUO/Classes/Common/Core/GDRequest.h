//
//  GDRequest.h
//  2HUO
//
//  Created by iURCoder on 4/30/16.
//  Copyright © 2016 iUR. All rights reserved.
//

#import "GDReq.h"

@interface GDRequest : GDReq

#pragma mark 用户

// 用户登录
+ (GDReq *)userLoginRequest;

// 获取学校列表
+ (GDReq *)getSchoolListRequest;

// 获取地址列表
+ (GDReq *)getAddressListRequest;

// 添加地址
+ (GDReq *)addAddressRequest;

// 修改地址
+ (GDReq *)updateAddressRequest;

// 删除地址
+ (GDReq *)deleteAddressRequest;

// 默认地址
+ (GDReq *)getDefAddressRequest;

#pragma mark  商品

// 获取分类列表
+ (GDReq *)getCommunityListRequest;

// 获取商品列表
+ (GDReq *)getPostListRequest;

// 发布商品
+ (GDReq *)addPostListRequest;

@end
