//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

#import "PINCacheTests.h"
#import "PINCache.h"

static NSString * const PINCacheTestName = @"PINCacheTest";
static const NSTimeInterval PINCacheTestBlockTimeout = 10.0;

@interface PINDiskCache()

- (NSString *)encodedString:(NSString *)string;

@end

@interface PINCacheTests ()
@property (strong, nonatomic) PINCache *cache;
@end

@implementation PINCacheTests

#pragma mark - XCTestCase -

- (void)setUp
{
    [super setUp];
    self.cache = [[PINCache alloc] initWithName:[[NSUUID UUID] UUIDString]];
    
    XCTAssertNotNil(self.cache, @"test cache does not exist");
}

- (void)tearDown
{
    [self.cache removeAllObjects];

    self.cache = nil;

    XCTAssertNil(self.cache, @"test cache did not deallocate");
    
    [super tearDown];
}

#pragma mark - Private Methods

- (UIImage *)image
{
    static UIImage *image = nil;
    
    if (!image) {
        NSError *error = nil;
        NSURL *imageURL = [[NSBundle mainBundle] URLForResource:@"Default-568h@2x" withExtension:@"png"];
        NSData *imageData = [[NSData alloc] initWithContentsOfURL:imageURL
                                                          options:NSDataReadingUncached
                                                            error:&error];
        image = [[UIImage alloc] initWithData:imageData scale:2.f];
    }

    NSAssert(image, @"test image does not exist");

    return image;
}

- (dispatch_time_t)timeout
{
    return dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PINCacheTestBlockTimeout * NSEC_PER_SEC));
}

#pragma mark - Tests -

- (void)testDiskCacheStringEncoding
{
    NSString *string = [self.cache.diskCache encodedString:@"http://www.test.de-<CoolStuff>?%"];
    XCTAssertTrue([string isEqualToString:@"http%3A%2F%2Fwww%2Etest%2Ede-<CoolStuff>?%25"]);
}

- (void)testCoreProperties
{
    PINCache *cache = [[PINCache alloc] initWithName:PINCacheTestName];
    XCTAssertTrue([cache.name isEqualToString:PINCacheTestName], @"wrong name");
    XCTAssertNotNil(cache.memoryCache, @"memory cache does not exist");
    XCTAssertNotNil(cache.diskCache, @"disk cache doe not exist");
}

- (void)testDiskCacheURL
{
    // Wait for URL to be created
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [self.cache objectForKey:@"" block:^(PINCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
      dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[self.cache.diskCache.cacheURL path] isDirectory:&isDir];

    XCTAssertTrue(exists, @"disk cache directory does not exist");
    XCTAssertTrue(isDir, @"disk cache url is not a directory");
}

- (void)testObjectSet
{
    NSString *key = @"key";
    __block UIImage *image = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.cache setObject:[self image] forKey:key block:^(PINCache *cache, NSString *key, id object) {
        image = (UIImage *)object;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    XCTAssertNotNil(image, @"object was not set");
}

- (void)testObjectSetWithDuplicateKey
{
    NSString *key = @"key";
    NSString *value1 = @"value1";
    NSString *value2 = @"value2";
    __block NSString *cachedValue = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.cache setObject:value1 forKey:key];
    [self.cache setObject:value2 forKey:key];
    
    [self.cache objectForKey:key block:^(PINCache *cache, NSString *key, id object) {
        cachedValue = (NSString *)object;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    XCTAssertEqual(cachedValue, value2, @"set did not overwrite previous object with same key");
}

- (void)testObjectContains
{
    NSString *key = @"key";
    NSString *value = @"value";
    
    [self.cache setObject:value forKey:key];
    
    // Synchronously
    XCTAssertTrue([self.cache containsObjectForKey:key], @"object was gone");
    
    // Asynchronously
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL cacheContainsObject = NO;
    [self.cache containsObjectForKey:key block:^(BOOL containsObject) {
        cacheContainsObject = containsObject;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    XCTAssertTrue(cacheContainsObject, @"object was gone");
}

- (void)testObjectGet
{
    NSString *key = @"key";
    __block UIImage *image = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    self.cache[key] = [self image];
    
    [self.cache objectForKey:key block:^(PINCache *cache, NSString *key, id object) {
        image = (UIImage *)object;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    XCTAssertNotNil(image, @"object was not got");
}

- (void)testObjectGetWithInvalidKey
{
    NSString *key = @"key";
    NSString *invalidKey = @"invalid";
    __block UIImage *image = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.cache[key] = [self image];

    [self.cache objectForKey:invalidKey block:^(PINCache *cache, NSString *key, id object) {
        image = (UIImage *)object;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    XCTAssertNil(image, @"object with non-existent key was not nil");
}

- (void)testObjectRemove
{
    NSString *key = @"key";
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    self.cache[key] = [self image];
    
    [self.cache removeObjectForKey:key block:^(PINCache *cache, NSString *key, id object) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    id object = self.cache[key];
    
    XCTAssertNil(object, @"object was not removed");
}

- (void)testObjectRemoveAll
{
    NSString *key1 = @"key1";
    NSString *key2 = @"key2";
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    self.cache[key1] = key1;
    self.cache[key2] = key2;
    
    [self.cache removeAllObjects:^(PINCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, [self timeout]);
    
    id object1 = self.cache[key1];
    id object2 = self.cache[key2];
    
    XCTAssertNil(object1, @"not all objects were removed");
    XCTAssertNil(object2, @"not all objects were removed");
    XCTAssertTrue(self.cache.memoryCache.totalCost == 0, @"memory cache cost was not 0 after removing all objects");
    XCTAssertTrue(self.cache.diskByteCount == 0, @"disk cache byte count was not 0 after removing all objects");
}

- (void)testMemoryCost
{
    NSString *key1 = @"key1";
    NSString *key2 = @"key2";

    [self.cache.memoryCache setObject:key1 forKey:key1 withCost:1];
    [self.cache.memoryCache setObject:key2 forKey:key2 withCost:2];
    
    XCTAssertTrue(self.cache.memoryCache.totalCost == 3, @"memory cache total cost was incorrect");

    [self.cache.memoryCache trimToCost:1];

    id object1 = self.cache.memoryCache[key1];
    id object2 = self.cache.memoryCache[key2];

    XCTAssertNotNil(object1, @"object did not survive memory cache trim to cost");
    XCTAssertNil(object2, @"object was not trimmed despite exceeding cost");
    XCTAssertTrue(self.cache.memoryCache.totalCost == 1, @"cache had an unexpected total cost");
}

- (void)testMemoryCostByDate
{
    NSString *key1 = @"key1";
    NSString *key2 = @"key2";

    [self.cache.memoryCache setObject:key1 forKey:key1 withCost:1];
    [self.cache.memoryCache setObject:key2 forKey:key2 withCost:2];

    [self.cache.memoryCache trimToCostByDate:1];

    id object1 = self.cache.memoryCache[key1];
    id object2 = self.cache.memoryCache[key2];

    XCTAssertNil(object1, @"object was not trimmed despite exceeding cost");
    XCTAssertNil(object2, @"object was not trimmed despite exceeding cost");
    XCTAssertTrue(self.cache.memoryCache.totalCost == 0, @"cache had an unexpected total cost");
}

- (void)testDiskByteCount
{
    self.cache[@"image"] = [self image];
    
    XCTAssertTrue(self.cache.diskByteCount > 0, @"disk cache byte count was not greater than zero");
}

- (void)testDiskByteCountWithExistingKey
{
    self.cache[@"image"] = [self image];
    NSUInteger initialDiskByteCount = self.cache.diskByteCount;
    self.cache[@"image"] = [self image];

    XCTAssertTrue(self.cache.diskByteCount == initialDiskByteCount, @"disk cache byte count should not change by adding object with existing key and size");

    self.cache[@"image2"] = [self image];

    XCTAssertTrue(self.cache.diskByteCount > initialDiskByteCount, @"disk cache byte count should increase with new key and object added to disk cache");
}

- (void)testOneThousandAndOneWrites
{
    NSUInteger max = 1001;
    __block NSInteger count = max;

    dispatch_queue_t queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    dispatch_group_t group = dispatch_group_create();
    
    for (NSUInteger i = 0; i < max; i++) {
        NSString *key = [[NSString alloc] initWithFormat:@"key %lu", (unsigned long)i];
        NSString *obj = [[NSString alloc] initWithFormat:@"obj %lu", (unsigned long)i];
        
        [self.cache setObject:obj forKey:key block:nil];

        dispatch_group_enter(group);
    }
    
    for (NSUInteger i = 0; i < max; i++) {
        NSString *key = [[NSString alloc] initWithFormat:@"key %lu", (unsigned long)i];
        
        [self.cache objectForKey:key block:^(PINCache *cache, NSString *key, id object) {
            dispatch_async(queue, ^{
                NSString *obj = [[NSString alloc] initWithFormat:@"obj %lu", (unsigned long)i];
                XCTAssertTrue([object isEqualToString:obj] == YES, @"object returned was not object set");
                count -= 1;
                dispatch_group_leave(group);
            });
        }];
    }
    
    dispatch_group_wait(group, [self timeout]);

    XCTAssertTrue(count == 0, @"one or more object blocks failed to execute, possible queue deadlock");
}

- (void)testMemoryWarningBlock
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block BOOL blockDidExecute = NO;

    self.cache.memoryCache.didReceiveMemoryWarningBlock = ^(PINMemoryCache *cache) {
        blockDidExecute = YES;
        dispatch_semaphore_signal(semaphore);
    };

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification
                                                        object:[UIApplication sharedApplication]];

    dispatch_semaphore_wait(semaphore, [self timeout]);

    XCTAssertTrue(blockDidExecute, @"memory warning block did not execute");
}

- (void)testBackgroundBlock
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block BOOL blockDidExecute = NO;

    self.cache.memoryCache.didEnterBackgroundBlock = ^(PINMemoryCache *cache) {
        blockDidExecute = YES;
        dispatch_semaphore_signal(semaphore);
    };
    
    BOOL isiOS8OrGreater = NO;
    NSString *reqSysVer = @"8";
    NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
    if ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending)
        isiOS8OrGreater = YES;

    if (isiOS8OrGreater) {
        //sending didEnterBackgroundNotification causes crash on iOS 8.
        NSNotification *notification = [NSNotification notificationWithName:UIApplicationDidEnterBackgroundNotification object:nil];
        [self.cache.memoryCache performSelector:@selector(didReceiveEnterBackgroundNotification:) withObject:notification];
        
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification
                                                            object:[UIApplication sharedApplication]];

    }
    
    dispatch_semaphore_wait(semaphore, [self timeout]);

    XCTAssertTrue(blockDidExecute, @"app background block did not execute");
}

- (void)testMemoryWarningProperty
{
    [self.cache.memoryCache setObject:@"object" forKey:@"object" block:nil];

    self.cache.memoryCache.removeAllObjectsOnMemoryWarning = NO;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block id object = nil;
    
    self.cache.memoryCache.didReceiveMemoryWarningBlock = ^(PINMemoryCache *cache) {
        object = cache[@"object"];
        dispatch_semaphore_signal(semaphore);
    };

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification
                                                        object:[UIApplication sharedApplication]];

    dispatch_semaphore_wait(semaphore, [self timeout]);

    XCTAssertNotNil(object, @"object was removed from the cache");
}

- (void)testMemoryCacheEnumerationWithWarning
{
    NSUInteger objectCount = 3;

    dispatch_apply(objectCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
        NSString *key = [[NSString alloc] initWithFormat:@"key %zd", index];
        NSString *obj = [[NSString alloc] initWithFormat:@"obj %zd", index];
        self.cache.memoryCache[key] = obj;
    });

    self.cache.memoryCache.removeAllObjectsOnMemoryWarning = NO;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block NSUInteger enumCount = 0;

    self.cache.memoryCache.didReceiveMemoryWarningBlock = ^(PINMemoryCache *cache) {
        [cache enumerateObjectsWithBlock:^(PINMemoryCache *cache, NSString *key, id object) {
            enumCount++;
        } completionBlock:^(PINMemoryCache *cache) {
            dispatch_semaphore_signal(semaphore);
        }];
    };

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification
                                                        object:[UIApplication sharedApplication]];

    dispatch_semaphore_wait(semaphore, [self timeout]);

    XCTAssertTrue(objectCount == enumCount, @"some objects were not enumerated");
}

- (void)testDiskCacheEnumeration
{
    NSUInteger objectCount = 3;
    
    dispatch_group_t group = dispatch_group_create();

    dispatch_apply(objectCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
        NSString *key = [[NSString alloc] initWithFormat:@"key %zd", index];
        NSString *obj = [[NSString alloc] initWithFormat:@"obj %zd", index];
        dispatch_group_enter(group);
        [self.cache.diskCache setObject:obj forKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
            dispatch_group_leave(group);
        }];
    });
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block NSUInteger enumCount = 0;

    [self.cache.diskCache enumerateObjectsWithBlock:^(PINDiskCache *cache, NSString *key, id <NSCoding> object, NSURL *fileURL) {
        enumCount++;
    } completionBlock:^(PINDiskCache *cache) {
        dispatch_semaphore_signal(semaphore);
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification
                                                        object:[UIApplication sharedApplication]];

    dispatch_semaphore_wait(semaphore, [self timeout]);

    XCTAssertTrue(objectCount == enumCount, @"some objects were not enumerated");
}

- (void)testDeadlocks
{
    NSString *key = @"key";
    NSUInteger objectCount = 1000;
    [self.cache setObject:[self image] forKey:key];
    dispatch_queue_t testQueue = dispatch_queue_create("test queue", DISPATCH_QUEUE_CONCURRENT);
    
    NSLock *enumCountLock = [[NSLock alloc] init];
    __block NSUInteger enumCount = 0;
    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger idx = 0; idx < objectCount; idx++) {
        dispatch_group_async(group, testQueue, ^{
            [self.cache objectForKey:key];
            [enumCountLock lock];
            enumCount++;
            [enumCountLock unlock];
        });
    }
    
    dispatch_group_wait(group, [self timeout]);
    XCTAssertTrue(objectCount == enumCount, @"was not able to fetch 1000 objects, possibly due to deadlock.");
}

- (void)testAgeLimit
{
    [self.cache removeAllObjects];
    NSString *key = @"key";
    self.cache[key] = [self image];
    [self.cache.memoryCache setAgeLimit:60];
    [self.cache.diskCache setAgeLimit:60];
    
    dispatch_group_t group = dispatch_group_create();
    
    __block id memObj = nil;
    __block id diskObj = nil;
    
    dispatch_group_enter(group);
    [self.cache.memoryCache objectForKey:key block:^(PINMemoryCache *cache, NSString *key, id object) {
        memObj = object;
        dispatch_group_leave(group);
    }];
    
    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
        diskObj = object;
        dispatch_group_leave(group);
    }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    XCTAssert(memObj != nil, @"should still be in memory cache");
    XCTAssert(diskObj != nil, @"should still be in disk cache");
    
    sleep(2);
    
    [self.cache.memoryCache setAgeLimit:1];
    [self.cache.diskCache setAgeLimit:1];
    
    dispatch_group_enter(group);
    [self.cache.memoryCache objectForKey:key block:^(PINMemoryCache *cache, NSString *key, id object) {
        memObj = object;
        dispatch_group_leave(group);
    }];
    
    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
        diskObj = object;
        dispatch_group_leave(group);
    }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    XCTAssert(memObj == nil, @"should not be in memory cache");
    XCTAssert(diskObj == nil, @"should not be in disk cache");
}

- (void)testWritingProtectionOption
{
  #if !TARGET_OS_IPHONE
    return;
  #endif
  
  #if TARGET_OS_SIMULATOR
    NSLog(@"Warning: file protection can't be tested on iPhone simulator");
    return;
  #endif
  
  self.cache.diskCache.writingProtectionOption = NSDataWritingFileProtectionCompleteUnlessOpen;
  
  NSString *key = @"key";
  __block NSURL *diskFileURL = nil;
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  [self.cache.diskCache setObject:[self image] forKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
    diskFileURL = fileURL;
    dispatch_semaphore_signal(semaphore);
  }];
  
  dispatch_semaphore_wait(semaphore, [self timeout]);
  
  NSError *error = nil;
  NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:diskFileURL.path error:&error];
  
  XCTAssertNil(error, @"error getting attributes of file");
  XCTAssertEqual(attributes[NSFileProtectionKey], NSFileProtectionCompleteUnlessOpen, @"file protection key is incorrect");
}

- (void)testTTLCacheObjectAccess {
    [self.cache removeAllObjects];
    NSString *key = @"key";
    [self.cache.memoryCache setAgeLimit:2];
    [self.cache.diskCache setAgeLimit:2];


    // The cache is going to clear at 2 seconds, set an object at 1 second, so that it misses the first cache clearing
    sleep(1);
    [self.cache setObject:[self image] forKey:key];

    // Wait until time 3 so that we know the object should be expired, the 1st cache clearing has happened, and the 2nd cache clearing hasn't happened yet
    sleep(2);

    [self.cache.diskCache setTtlCache:YES];
    [self.cache.memoryCache setTtlCache:YES];

    dispatch_group_t group = dispatch_group_create();

    __block id memObj = nil;
    __block id diskObj = nil;

    dispatch_group_enter(group);
    [self.cache.memoryCache objectForKey:key block:^(PINMemoryCache *cache, NSString *key, id object) {
        memObj = object;
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
        diskObj = object;
        dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // If the cache is supposed to behave like a TTL cache, then the object shouldn't appear to be in the cache
    XCTAssertNil(memObj, @"should not be in memory cache");
    XCTAssertNil(diskObj, @"should not be in disk cache");

    [self.cache.diskCache setTtlCache:NO];
    [self.cache.memoryCache setTtlCache:NO];

    memObj = nil;
    diskObj = nil;

    dispatch_group_enter(group);
    [self.cache.memoryCache objectForKey:key block:^(PINMemoryCache *cache, NSString *key, id object) {
        memObj = object;
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache *cache, NSString *key, id<NSCoding> object, NSURL *fileURL) {
        diskObj = object;
        dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
     // If the cache is NOT supposed to behave like a TTL cache, then the object should appear to be in the cache because it hasn't been cleared yet
    XCTAssertNotNil(memObj, @"should still be in memory cache");
    XCTAssertNotNil(diskObj, @"should still be in disk cache");
}

- (void)testTTLCacheObjectEnumeration {
    [self.cache removeAllObjects];
    NSString *key = @"key";
    [self.cache.memoryCache setAgeLimit:2];
    [self.cache.diskCache setAgeLimit:2];


    // The cache is going to clear at 2 seconds, set an object at 1 second, so that it misses the first cache clearing
    sleep(1);
    self.cache[key] = [self image];

    // Wait until time 3 so that we know the object should be expired, the 1st cache clearing has happened, and the 2nd cache clearing hasn't happened yet
    sleep(2);

    [self.cache.diskCache setTtlCache:YES];
    [self.cache.memoryCache setTtlCache:YES];

    // Wait for ttlCache to be set
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // With the TTL cache enabled, we expect enumerating over the caches to yield 0 objects
    NSUInteger expectedObjCount = 0;
    __block NSUInteger objCount = 0;
    [self.cache.diskCache enumerateObjectsWithBlock:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
      objCount++;
    }];

    XCTAssertEqual(objCount, expectedObjCount, @"Expected %lu objects in the cache", (unsigned long)expectedObjCount);

    objCount = 0;
    [self.cache.memoryCache enumerateObjectsWithBlock:^(PINMemoryCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
      objCount++;
    }];

    XCTAssertEqual(objCount, expectedObjCount, @"Expected %lu objects in the cache", (unsigned long)expectedObjCount);

    [self.cache.diskCache setTtlCache:NO];
    [self.cache.memoryCache setTtlCache:NO];

    // Wait for ttlCache to be set
    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // With the TTL cache disabled, we expect enumerating over the caches to yield 1 object each, since the 2nd cache clearing hasn't happened yet
    expectedObjCount = 1;
    objCount = 0;
    [self.cache.diskCache enumerateObjectsWithBlock:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
      objCount++;
    }];

    XCTAssertEqual(objCount, expectedObjCount, @"Expected %lu objects in the cache", (unsigned long)expectedObjCount);

    objCount = 0;
    [self.cache.memoryCache enumerateObjectsWithBlock:^(PINMemoryCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
      objCount++;
    }];

    XCTAssertEqual(objCount, expectedObjCount, @"Expected %lu objects in the cache", (unsigned long)expectedObjCount);
}

- (void)testTTLCacheFileURLForKey {
    NSString *key = @"key";

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block NSURL *objectURL = nil;
    [self.cache.diskCache setObject:[self image] forKey:key block:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
      objectURL = fileURL;
      dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    XCTAssertNotNil(objectURL, @"objectURL should have a non-nil URL");

    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[objectURL path] error:&error];
    NSDate *initialModificationDate = attributes[NSFileModificationDate];
    XCTAssertNotNil(initialModificationDate, @"The saved file should have a non-nil modification date");

    // Wait a moment to ensure that the file modification time can be changed to something different
    sleep(1);

    [self.cache.diskCache setTtlCache:YES];
    // Wait for ttlCache to be set
    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
      dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [self.cache.diskCache fileURLForKey:key];

    attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[objectURL path] error:nil];
    NSDate *ttlCacheEnabledModificationDate = attributes[NSFileModificationDate];
    XCTAssertNotNil(ttlCacheEnabledModificationDate, @"The saved file should have a non-nil modification date");

    XCTAssertEqualObjects(initialModificationDate, ttlCacheEnabledModificationDate, @"The modification date shouldn't change when accessing the file URL, when ttlCache is enabled");

    [self.cache.diskCache setTtlCache:NO];
    // Wait for ttlCache to be set
    dispatch_group_enter(group);
    [self.cache.diskCache objectForKey:key block:^(PINDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable fileURL) {
      dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [self.cache.diskCache fileURLForKey:key];

    attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[objectURL path] error:nil];
    NSDate *ttlCacheDisabledModificationDate = attributes[NSFileModificationDate];
    XCTAssertNotNil(ttlCacheDisabledModificationDate, @"The saved file should have a non-nil modification date");

    XCTAssertNotEqualObjects(initialModificationDate, ttlCacheDisabledModificationDate, @"The modification date should change when accessing the file URL, when ttlCache is not enabled");

}

@end
