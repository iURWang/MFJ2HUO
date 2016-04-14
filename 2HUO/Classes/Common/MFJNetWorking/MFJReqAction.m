//
//  MFJReqAction.m
//  2HUO
//
//  Created by iURCoder on 4/1/16.
//  Copyright © 2016 iUR. All rights reserved.
//

#import "MFJReqAction.h"
#import "MFJReq.h"
#import "MFJGroupReq.h"
#import "TMCache.h"
#import "MFJSecurityPolicy.h"

static dispatch_queue_t MFJ_req_task_creation_queue() {
    static dispatch_queue_t MFJ_req_task_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MFJ_req_task_creation_queue =
        dispatch_queue_create("me.iur.cool.networking.durandal.req.creation", DISPATCH_QUEUE_SERIAL);
    });
    return MFJ_req_task_creation_queue;
}

static MFJReqAction *instance       = nil;

@interface MFJReqAction ()

@property(nonatomic,assign)BOOL cacheEnable;
@property(nonatomic,assign)BOOL dataFromCache;
@property (nonatomic, strong) NSCache *sessionManagerCache;
@property (nonatomic, strong) NSCache *sessionTasksCache;
@property (nonatomic, copy  ) listenCallBack listenBlock;

@end

@implementation MFJReqAction

+ (nonnull instancetype)shareInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (nonnull instancetype)action
{
    return [[self alloc] init];
}

-(void)notUseCache
{
    _cacheEnable = NO;
}

-(void)useCache{
    _cacheEnable = YES;
}

-(void)readFromCache{
    _dataFromCache = YES;
}
-(void)notReadFromCache{
    _dataFromCache = NO;
}


-(NSURLSessionDataTask *)Upload:(MFJReq *)req{
    NSString *url = [self requesturlFromMFJRequest:req];
    NSDictionary *requestParams = nil;
    
    if(req.appendPathInfo.isNotEmpty){
        url = [url stringByAppendingString:req.appendPathInfo];
    }else{
        requestParams = req.params;
    }
    
#ifdef DEBUG
    NSLog(@"upload url: %@", url);
#endif
    
    req.url = [NSURL URLWithString:url];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    manager.responseSerializer = [self responseSerializerForRequest:req];
    
    NSDictionary *file = req.requestFiles;
    NSError * error;
    
    void (^block)(id<AFMultipartFormData>) = ^void(id<AFMultipartFormData> formData) {
        [file enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            if([obj isKindOfClass:[NSURL class]]){
                [formData appendPartWithFileURL:obj name:key error:nil];
            }else if([obj isKindOfClass:[NSData class]]){
                [formData appendPartWithFormData:obj name:key];
            }else if([obj isKindOfClass:[NSString class]]){
                [formData appendPartWithFileURL:[NSURL fileURLWithPath:obj] name:key error:nil];
            }else if ([obj isKindOfClass:[UIImage class]]){
                NSData * imageData = UIImageJPEGRepresentation([file objectForKey:key], 0.5);
                [formData appendPartWithFileData:imageData
                                            name:key
                                        fileName:[NSString stringWithFormat:@"%@.jpg", key]
                                        mimeType:@"image/jpeg"];
            }
        }];
    };
    
    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST" URLString:url parameters:requestParams constructingBodyWithBlock:block error:&error];
    
    if(req.httpHeaderFields.isNotEmpty){
        [req.httpHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    if (req.timeoutInterval != 0) {
        request.timeoutInterval = req.timeoutInterval;
    }
    
    NSURLSessionDataTask *task = [manager uploadTaskWithStreamedRequest:request progress:^(NSProgress * uploadProgress) {
        if (req.requestProgressBlock) {
            req.requestProgressBlock(uploadProgress);
        }
    } completionHandler:^(NSURLResponse * response, NSDictionary*responseObject, NSError * error) {
        
        if (error == nil) {
            req.output = responseObject;
            [self checkCode:req];
        }else{
            req.error = error;
            [self requestFaild:req];
        }
    }];
    
    req.task = task;
    
    [task resume];
    return task;
}


-(NSURLSessionDownloadTask *)Download:(MFJReq *)req{
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:req.downloadUrl]];
    
    if (req.timeoutInterval != 0) {
        request.timeoutInterval = req.timeoutInterval;
    }
    
    if(req.httpHeaderFields.isNotEmpty){
        [req.httpHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    
    __weak typeof(MFJReq *) weakReq = req;
    NSURLSessionDownloadTask *task = [manager downloadTaskWithRequest:request progress:^(NSProgress * downloadProgress) {
        __strong typeof(MFJReq *) strongReq = weakReq;
        if (strongReq.requestProgressBlock) {
            strongReq.requestProgressBlock(downloadProgress);
        }
    } destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        
        __strong typeof(MFJReq *) strongReq = weakReq;
        NSURL *documentsDirectoryURL = [NSURL URLWithString:strongReq.targetPath];
        return [documentsDirectoryURL URLByAppendingPathComponent:[response suggestedFilename]];
        
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        
        __strong typeof(MFJReq *) strongReq = weakReq;
        strongReq.error = error;
        
    }];
    
    [task resume];
    return task;
}


- (void)Send:(nonnull MFJReq  *)req
{
    NSParameterAssert(req);
    
    if (req.downloadUrl.isNotEmpty && req.targetPath.isNotEmpty) {
        // 下载
        [self Download:req];
        return;
    }
    if (req.requestFiles.isNotEmpty) {
        // 上传
        [self Upload:req];
        return;
    }
    
    if (req.cachePolicy != MFJRequestCachePolicyNoCache) {
        [self useCache];
    }
    if (req.cachePolicy == MFJRequestCachePolicyReadCache) {
        [self readFromCache];
    }
    if (req.cachePolicy == MFJRequestCachePolicyReadCacheFirst) {
        if (req.isFirstRequest) {
            [self readFromCache];
        }else{
            [self notReadFromCache];
        }
    }
    
    dispatch_async(MFJ_req_task_creation_queue(), ^{
        
        NSMutableURLRequest *request = [self managerRequestWithRequest:req];
        AFURLSessionManager *sessionManager = [self sessionManagerWithRequest:req];
        
        if (!sessionManager) {
            return;
        }
        if ([[NSThread currentThread] isMainThread]) {
            [self requestNotStrat:req];
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self requestNotStrat:req];
            });
        }
        [self _send:req request:request manager:sessionManager];
    });
}

- (void)sendRequests:(nonnull MFJGroupReq *)groupreq
{
    NSParameterAssert(groupreq);
    
    NSAssert([[groupreq.requestsSet valueForKeyPath:@"hash"] count] == [groupreq.requestsSet count],
             @"Should not have same API");
    
    dispatch_group_t batch_api_group = dispatch_group_create();
    __weak typeof(self) weakSelf = self;
    [groupreq.requestsSet enumerateObjectsUsingBlock:^(id req, BOOL * stop) {
        dispatch_group_enter(batch_api_group);
        
        __strong typeof (weakSelf) strongSelf = weakSelf;
        AFURLSessionManager *sessionManager = [strongSelf sessionManagerWithRequest:req];
        NSMutableURLRequest *request = [self managerRequestWithRequest:req];
        if (!sessionManager) {
            *stop = YES;
            dispatch_group_leave(batch_api_group);
        }
        sessionManager.completionGroup = batch_api_group;
        [self _send:req request:request manager:sessionManager andCompletionGroup:batch_api_group];
        
    }];
    dispatch_group_notify(batch_api_group, dispatch_get_main_queue(), ^{
        if (groupreq.delegate) {
            [groupreq.delegate groupRequestsDidFinished:groupreq];
        }
    });
}

-(NSURLSessionDataTask *)_send:(MFJReq *)req request:(NSMutableURLRequest *)request manager:(AFURLSessionManager *)manager{
    return [self _send:req request:request manager:manager andCompletionGroup:nil];
}

-(NSURLSessionDataTask *)_send:(MFJReq *)req request:(NSMutableURLRequest *)request manager:(AFURLSessionManager *)manager andCompletionGroup:(dispatch_group_t)completionGroup
{
    NSParameterAssert(req);
    NSParameterAssert(manager);
    req.isFirstRequest = NO;
    
    if ([self.sessionTasksCache objectForKey:req.requestID]) {
        // 请求正在执行中
        return nil;
    }
    
    __weak typeof(self) weakSelf = self;
    
    void (^completion)(NSURLResponse * response, NSDictionary *responseObject, NSError * error)
    = ^(NSURLResponse * response, NSDictionary *responseObject, NSError * error) {
        
        __strong typeof (weakSelf) strongSelf = weakSelf;
        
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
        
        if(error == nil){
            req.output = responseObject;
            if(_cacheEnable && [strongSelf doCheckCode:req]){
                [[TMCache sharedCache] setObject:responseObject forKey:req.requestID block:^(TMCache *cache, NSString *key, id object) {
                    NSLog(@"%@ has cached",request.URL);
                }];
            }
            [strongSelf checkCode:req];
            if (completionGroup) {
                dispatch_group_leave(completionGroup);
            }
        }else{
            // error
            req.error = error;
            [self requestFaild:req];
            if (completionGroup) {
                dispatch_group_leave(completionGroup);
            }
        }
        [strongSelf.sessionTasksCache removeObjectForKey:req.requestID];
        
    };
    
    
    if ([[NSThread currentThread] isMainThread]) {
        // will send
        [self requestStartSend:req];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            // will send
            [self requestStartSend:req];
        });
    }
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    NSURLSessionDataTask *task = [manager dataTaskWithRequest:request completionHandler:completion];
    
    if (task) {
        [self.sessionTasksCache setObject:task forKey:req.requestID];
        req.task = task;
    }
    
    if ([[NSThread currentThread] isMainThread]) {
        [self requestSending:req];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self requestSending:req];
        });
    }
    
    req.output = [[TMCache sharedCache] objectForKey:req.requestID];
    if (_dataFromCache == YES && req.output !=nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (0.1f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkCode:req];
        });
    }
    [task resume];
    return task;
}


- (void)cancelRequest:(nonnull MFJReq  *)req
{
    dispatch_async(MFJ_req_task_creation_queue(), ^{
        NSURLSessionDataTask *dataTask = [self.sessionTasksCache objectForKey:req.requestID];
        [self.sessionTasksCache removeObjectForKey:req.requestID];
        if (dataTask) {
            [dataTask cancel];
            [self requestCancle:req];
        }
    });
}

- (NSMutableURLRequest *)managerRequestWithRequest:(MFJReq *)req
{
    
    NSString *url = [self requesturlFromMFJRequest:req];
    NSDictionary *requestParams = nil;
    
    if(req.appendPathInfo.isNotEmpty){
        url = [url stringByAppendingString:req.appendPathInfo];
    }else{
        requestParams = req.params;
    }
    
#ifdef DEBUG
    NSLog(@"request url: %@", url);
#endif
    
    req.url = [NSURL URLWithString:url];
    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] requestWithMethod:req.METHOD URLString:url parameters:requestParams error:nil];
    
    if(req.httpHeaderFields.isNotEmpty){
        [req.httpHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    if (req.timeoutInterval != 0) {
        request.timeoutInterval = req.timeoutInterval;
    }
    
    return request;
}

#pragma mark - AFSessionManager
- (AFURLSessionManager *)sessionManagerWithRequest:(MFJReq *)req {
    NSParameterAssert(req);
    
   // responseSerializer
    AFHTTPResponseSerializer *responseSerializer = [self responseSerializerForRequest:req];
    
    // AFURLSessionManager
    AFURLSessionManager *sessionManager;
    sessionManager = [self.sessionManagerCache objectForKey:req.requestID];
    if (!sessionManager) {
        sessionManager = [self newSessionManagerWithBaseUrlStr:req.requestID];
        [self.sessionManagerCache setObject:sessionManager forKey:req.requestID];
    }
    
    sessionManager.responseSerializer    = responseSerializer;
    sessionManager.securityPolicy        = [self securityPolicyWithAPI:req];
    
    return sessionManager;
}

- (AFURLSessionManager *)newSessionManagerWithBaseUrlStr:(NSString *)baseUrlStr {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.HTTPMaximumConnectionsPerHost = MAX_HTTP_CONNECTION_PER_HOST;
    return [[AFURLSessionManager alloc] initWithSessionConfiguration:sessionConfig];
}


- (AFHTTPResponseSerializer *)responseSerializerForRequest:(MFJReq *)req {
    NSParameterAssert(req);
    AFHTTPResponseSerializer *responseSerializer;
    if ([req responseSerializer] == MFJResponseSerializerTypeHTTP) {
        responseSerializer = [AFHTTPResponseSerializer serializer];
    } else {
        responseSerializer = [AFJSONResponseSerializer serializer];
    }
    responseSerializer.acceptableContentTypes = [req acceptableContentTypes];
    return responseSerializer;
}

- (AFSecurityPolicy *)securityPolicyWithAPI:(MFJReq *)req {
    NSUInteger pinningMode                  = req.securityPolicy.SSLPinningMode;
    AFSecurityPolicy *securityPolicy        = [AFSecurityPolicy policyWithPinningMode:pinningMode];
    securityPolicy.allowInvalidCertificates = req.securityPolicy.allowInvalidCertificates;
    securityPolicy.validatesDomainName      = req.securityPolicy.validatesDomainName;
    return securityPolicy;
}

- (NSString *)requesturlFromMFJRequest:(MFJReq *)req
{
    NSString * url = @"";
    if(req.STATICPATH.isNotEmpty){
        url = req.STATICPATH;
        if (![url hasPrefix:@"http"]) {
            url = [@"http://" stringByAppendingString:url];
        }
    }else if(req.HOST.isNotEmpty){
        NSString * host = req.HOST,*path = req.PATH,*scheme;
        if (![host hasSuffix:@"/"]) {
             host = [host stringByAppendingString:@"/"];
        }
        if ([path hasPrefix:@"/"]) {
            path = [path substringFromIndex:1];
        }
        if (req.SCHEME.isNotEmpty) {
            scheme = req.SCHEME;
        }else{
            scheme = @"http";
        }
        if ([host hasPrefix:@"http://"]) {
            scheme = @"http";
            host = [host substringFromIndex:7];
        }
        if ([host hasPrefix:@"https://"]) {
            scheme = @"https";
            host = [host substringFromIndex:8];
        }
        url = [NSString stringWithFormat:@"%@://%@%@",scheme,host,path];
    }else{
        NSString * host = kHostPath,*path = req.PATH,*scheme = @"http";
        if ([host hasPrefix:@"http://"]) {
            scheme = @"http";
            host = [host substringFromIndex:7];
        }
        if ([host hasPrefix:@"https://"]) {
            scheme = @"https";
            host = [host substringFromIndex:8];
        }
        if (![host hasSuffix:@"/"]) {
            host = [host stringByAppendingString:@"/"];
        }
        if ([path hasPrefix:@"/"]) {
            path = [path substringFromIndex:0];
        }
        url = [NSString stringWithFormat:@"%@://%@%@",scheme,host,path];
    }
    return url;
}

- (NSCache *)sessionManagerCache {
    if (!_sessionManagerCache) {
        _sessionManagerCache = [[NSCache alloc] init];
    }
    return _sessionManagerCache;
}

- (NSCache *)sessionTasksCache {
    if (!_sessionTasksCache) {
        _sessionTasksCache = [[NSCache alloc] init];
    }
    return _sessionTasksCache;
}

- (void)requestComplete:(MFJReq *)req obj:(id)responseobject
{
    if (responseobject == nil) {
        req.output     = nil;
    }
    if ([responseobject isKindOfClass:[NSString class]]) {
        NSData * data = [((NSString *)responseobject) dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        id output = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
        if (error) {
            NSLog(@"url:%@ response error:%@",req.url, error);
        }
        req.output = output;
        req.responseString = responseobject;
    }
    if ([responseobject isKindOfClass:[NSData class]]) {
        NSError *error = nil;
        id output = [NSJSONSerialization JSONObjectWithData:responseobject options:kNilOptions error:&error];
        if (error) {
            NSLog(@"url:%@ response error:%@",req.url, error);
        }
        req.output = output;
        req.responseString = [[NSString alloc] initWithData:responseobject encoding:NSUTF8StringEncoding];
    }
    if ([responseobject isKindOfClass:[NSArray class]]) {
        req.output     = @{@"data":responseobject};
    }
    if ([responseobject isKindOfClass:[NSDictionary class]]) {
        req.output     = responseobject;
    }
}

- (void)listenRequest:(MFJReq *)req
{
    if (self.listenBlock) {
        self.listenBlock(req);
    }
}

- (void)request:(MFJReq *)req statusHaveChanged:(MFJRequestStatus)status
{
    req.status = status;
    [self listenRequest:req];
}

- (void)requestNotStrat:(MFJReq *)req
{
    [self request:req statusHaveChanged:MFJRequestStatusNotStart];
}

- (void)requestStartSend:(MFJReq *)req
{
    [self request:req statusHaveChanged:MFJRequestStatusStart];
}

- (void)requestSending:(MFJReq *)req
{
    [self request:req statusHaveChanged:MFJRequestStatusSending];
}

- (void)requestSucccess:(MFJReq *)req
{
    [self request:req statusHaveChanged:MFJRequestStatusSuccess];
}

- (void)requestCancle:(MFJReq *)req
{
    [self request:req statusHaveChanged:MFJRequestStatusCancle];
}

- (void)requestFaild:(MFJReq *)req
{
    if(req.error.userInfo!= nil){
        req.message = [req.error.userInfo objectForKey:@"NSLocalizedDescription"];
        [self request:req statusHaveChanged:MFJRequestStatusFailed];
    }
    if (req.error.code == -1001) {
        req.isTimeout = YES;
        [self request:req statusHaveChanged:MFJRequestStatusTimeOut];
    }else{
        [self request:req statusHaveChanged:MFJRequestStatusFailed];
    }
}

- (void)requestError:(MFJReq *)req
{
    [self request:req statusHaveChanged:MFJRequestStatusError];
}

- (void)checkCode:(MFJReq *)req
{
    if([self doCheckCode:req]){
        [self requestSucccess:req];
    }else{
        [self requestError:req];
    }
    
}

-(BOOL)doCheckCode:(MFJReq *)req{
    if (req.needCheckCode) {
        NSString * exactitudeKey      = req.exactitudeKey;
        NSString * exactitudeKeyPath  = req.exactitudeKeyPath;
        NSString * code = [req.output objectAtPath:exactitudeKeyPath];
        if ([code isKindOfClass:[NSNumber class]]) {
            code = [(NSNumber *)code stringValue];
        }
        req.codeKey = code;
        if(code && [code isEqualToString:exactitudeKey]){
            return true;
        }else{
            return false;
        }
    }else{
        return true;
    }
}

- (void)listen:(listenCallBack)block
{
    if (block) {
        self.listenBlock = block;
    }
}

@end
