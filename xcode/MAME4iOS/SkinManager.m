//
//  SkinManager.m
//  MAME4iOS
//
//  Created by Todd Laney on 7/11/20.
//  Copyright © 2020 Seleuco. All rights reserved.
//

#import "SkinManager.h"
#import "EmulatorController.h"
#import "ZipFile.h"
#import "Globals.h"

#define DebugLog 1
#if DebugLog == 0
#define NSLog(...) (void)0
#endif

@implementation SkinManager {
    NSString* _skin_name;
    NSMutableArray<NSString*>* _skin_paths;
    NSMutableArray<NSDictionary*>* _skin_infos;
    NSCache* _image_cache;
}

static NSArray* g_skin_list;

//
// return the list of valid Skins
//
+ (NSArray<NSString*>*)getSkinNames {
    
    if (g_skin_list != nil)
        return g_skin_list;
    
    NSMutableArray* skins = [[NSMutableArray alloc] init];

    // add in the Default skin always.
    [skins addObject:kSkinNameDefault];
    
    // get built-in skins
    NSString* path = [NSString stringWithUTF8String:get_resource_path("skins")];
    NSArray* files = [[NSFileManager.defaultManager enumeratorAtPath:path] allObjects];
    
    // add any custom skins
    path = [NSString stringWithUTF8String:get_documents_path("skins")];
    files = [files arrayByAddingObjectsFromArray:[[NSFileManager.defaultManager enumeratorAtPath:path] allObjects]];
    
    NSArray* roms = [EmulatorController romList];
    
    for (NSString* file in files) {
        // dont let user select as the default Skin a ROM specific one.
        if ([roms containsObject:file.stringByDeletingPathExtension.lowercaseString])
            continue;
        if ([file.pathExtension.uppercaseString isEqualToString:@"ZIP"])
            [skins addObject:file.lastPathComponent.stringByDeletingPathExtension];
    }
    
    g_skin_list = skins;
    return skins;
}

// factory reset, delete all Skins
+ (void)reset {
    // delete all files in Skin dir.
    NSString* skins_path = [NSString stringWithUTF8String:get_documents_path("skins")];
    [[NSFileManager defaultManager] removeItemAtPath:skins_path error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:skins_path withIntermediateDirectories:NO attributes:nil error:nil];
    g_skin_list = nil;
}

- (instancetype)init {
    self = [super init];
    return self;
}

// skin name is a comma separated list
- (void)setCurrentSkin:(NSString*)name {
    
    if (name == nil || name.length == 0)
        name = kSkinNameDefault;
    
    if ([_skin_name isEqualToString:name])
        return;
    
    NSArray* names = [name componentsSeparatedByString:@","];
    
    NSLog(@"LOADING SKIN: %@", names);
    
    _skin_name = name;
    _skin_paths = nil;
    _skin_infos = [[NSMutableArray alloc] init];
    _image_cache = nil;
    
    // add any custom button layout (<Name>.json, if found)
    // NOTE Custom layout *overrides* json in the Skin, so we add it first
    NSString* path = [NSString stringWithFormat:@"%s/%@.json", get_documents_path("skins"), names.lastObject];
    [self addInfo:[NSData dataWithContentsOfFile:path]];
    
    for (NSString* name in names) {
        
        // if skin name is empty ignore it (a rom parent can be "0", so ignore that too)
        if (name.length == 0 || [name isEqualToString:@"0"])
            continue;

        // look for the Skin first in the user directory, then as a resource, else fail to default.
        NSString* path = [NSString stringWithFormat:@"%s/%@.zip", get_documents_path("skins"), name];
        
        if (![NSFileManager.defaultManager fileExistsAtPath:path])
            path = [NSString stringWithFormat:@"%s/%@.zip", get_resource_path("skins"), name];
        
        if (![NSFileManager.defaultManager fileExistsAtPath:path])
            continue;
        
        if ([_skin_paths containsObject:path])
            continue;
        
        _skin_paths = _skin_paths ?: [[NSMutableArray alloc] init];
        [_skin_paths addObject:path];

        // load skin.json if present.
        [self addInfo:[self loadData:@"skin.json" from:path]];
    }
    
    // add our Default layout file in SKIN_1
    NSData* info = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:get_resource_path("SKIN_1/skin.json")]];
    assert(info != nil);
    [self addInfo:info];
    
    NSLog(@"SKIN: %@\n%@\n%@", name, _skin_paths, _skin_infos);
}

// discard any cached data, new skin files have been added, force setCurrentSkin to re-load.
- (void)reload {
    g_skin_list = nil;
    NSString* name = _skin_name;
    _skin_name = nil;
    [self setCurrentSkin:name];
}

- (void)addInfo:(NSData*)data {
    if (data != nil) {
        NSError* error = nil;
        NSMutableDictionary* info = [[NSJSONSerialization JSONObjectWithData:data options:0 error:&error] mutableCopy];
        
        if (![info isKindOfClass:[NSDictionary class]]) {
            NSLog(@"INVALID JSON: %@", error);
            assert(FALSE);
            return;
        }
        
        // if a skin has only one of portrait, portrait_tall use it on both devices.
        if (info[@"portrait"] == nil && info[@"portrait_tall"] != nil)
            info[@"portrait"] = info[@"portrait_tall"];
        if (info[@"portrait_tall"] == nil && info[@"portrait"] != nil)
            info[@"portrait_tall"] = info[@"portrait"];
        
        // if a skin has only one of landscape, landscape_wide use it on both devices.
        if (info[@"landscape"] == nil && info[@"landscape_wide"] != nil)
            info[@"landscape"] = info[@"landscape_wide"];
        if (info[@"landscape_wide"] == nil && info[@"landscape"] != nil)
            info[@"landscape_wide"] = info[@"landscape"];
        
        [_skin_infos addObject:[info copy]];
    }
}

- (nullable NSData *)loadData:(NSString *)name from:(NSString*)path {
    NSString* uname = name.uppercaseString;
    __block NSData* data = nil;
    [ZipFile enumerate:path withOptions:ZipFileEnumFiles usingBlock:^(ZipFileInfo* info) {
        if (data != nil)
            return;
        if ([info.name.uppercaseString isEqualToString:uname])
            data = info.data;
        else if ([info.name.lastPathComponent.uppercaseString isEqualToString:uname])
            data = info.data;
        else if ([info.name.lastPathComponent.stringByDeletingPathExtension.uppercaseString isEqualToString:uname])
            data = info.data;
    }];
    return data;
}

- (nullable NSData *)loadData:(NSString *)name {
    for (NSString* path in _skin_paths) {
        NSData* data = [self loadData:name from:path];
        if (data != nil)
            return data;
    }
    return nil;
}

- (nullable UIImage *)loadImage:(NSString *)name {
    
    if (_image_cache == nil)
        _image_cache = [[NSCache alloc] init];
    
    UIImage* image = [_image_cache objectForKey:name];
    
    if ([image isKindOfClass:[UIImage class]])
        return image;
    if (image != nil)
        return nil;
    
    NSLog(@"SKIN IMAGE LOAD: %@", name);
    
    // cache miss, look for the image...
    // 1. in the skin file(s)
    NSData* data = [self loadData:name];
    if (data != nil)
        image = [UIImage imageWithData:data];

    // 2. as a resource (in SKIN_1)
    if (image == nil)
        image = [UIImage imageNamed:[NSString stringWithFormat:@"SKIN_1/%@", name]];

    // 3. as a resource
    if (image == nil)
        image = [UIImage imageNamed:name];
    
    if (image == nil)
        NSLog(@"SKIN IMAGE NOT FOUND: %@", name);

    [_image_cache setObject:(image ?: [NSNull null]) forKey:name];
    return image;
}

// get a value from one of the skin.json files, in priority order.
- (id)valueForKeyPath:(NSString*)keyPath {
    for (NSDictionary* info in _skin_infos) {
        id value = [info valueForKeyPath:keyPath];
        if (value != nil)
            return value;
    }
    return nil;
}

#pragma mark skin export template

// all possible files in a Skin, used to export a template
+ (NSArray<NSString*>*)getSkinFiles {

    NSMutableArray* files = [[NSMutableArray alloc] init];
    
    // get built-in images
    NSString* path = [NSString stringWithUTF8String:get_resource_path("SKIN_1")];
    for (NSString* file in [NSFileManager.defaultManager enumeratorAtPath:path]) {
        if ([file.pathExtension.uppercaseString isEqualToString:@"PNG"])
            [files addObject:file];
    }
    
    // add other images/etc
    [files addObjectsFromArray:@[
            @"skin.json", @"README.md",
            @"border", @"background",
            @"stick-U", @"stick-D", @"stick-L", @"stick-R",
            @"stick-UL", @"stick-DL", @"stick-DR", @"stick-UR",
    ]];
    
    return files;
}

- (NSDictionary*)getSkinInfo:(BOOL)isDefault {
    NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
    NSDictionary* defaults = _skin_infos.lastObject;
    
    // copy all the values from our default skin.json
    for (NSString* section in [defaults allKeys]) {
        if (![defaults[section] isKindOfClass:[NSDictionary class]])
              continue;
        
        dict[section] = [[NSMutableDictionary alloc] init];
        for (NSString* key in [defaults[section] allKeys]) {
            NSString* keyPath = [NSString stringWithFormat:@"%@.%@", section, key];
            id value = [self valueForKeyPath:keyPath];
            assert(value != nil);
            if (isDefault || [section isEqualToString:@"info"] || ![value isEqual:[defaults valueForKeyPath:keyPath]])
                [dict setValue:value forKeyPath:keyPath];
        }
        if ([dict[section] count] == 0)
            dict[section] = nil;
    }

    return dict;
}

// export the current skin data, if the skin is the default skin export everything, else only the changes.
- (BOOL)exportTo:(NSString*)path progressBlock:(nullable BOOL (NS_NOESCAPE ^)(double progress))block {
    NSArray* files = [SkinManager getSkinFiles];
    BOOL isDefault = [[_skin_name componentsSeparatedByString:@","].lastObject isEqualToString:kSkinNameDefault];
    
    NSLog(@"SKIN EXPORT: %@\n%@", path, files);

    return [ZipFile exportTo:path fromItems:files withOptions:ZipFileWriteFiles usingBlock:^ZipFileInfo * (NSString* name) {
        
        if (block) {
            BOOL cancel = block((double)[files indexOfObject:name] / [files count]);
            if (cancel)
                return nil;
        }
        
        if (name.pathExtension.length == 0)
            name = [name stringByAppendingPathExtension:@"png"];
        
        NSData* data = nil;
        
        if ([name isEqualToString:@"skin.json"])
            data = [NSJSONSerialization dataWithJSONObject:[self getSkinInfo:isDefault] options:NSJSONWritingPrettyPrinted error:nil];
        else if ([name isEqualToString:@"README.md"])
            data = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:[NSString stringWithFormat:@"skins/%@", name] ofType:nil]];
        else if (isDefault)
            data = UIImagePNGRepresentation([self loadImage:name]);
        else {
            data = UIImagePNGRepresentation([self loadImage:name]);
            UIImage* image = [UIImage imageNamed:[NSString stringWithFormat:@"SKIN_1/%@", name]];

            if (image != nil && [data isEqualToData:UIImagePNGRepresentation(image)])
                data = nil;
        }

        if (data != nil)
            NSLog(@"    FILE: %@ (%d bytes)", name, (int)[data length]);
        else
            NSLog(@"    FILE: %@ ** SKIPPED **", name);
        
        ZipFileInfo* info = [[ZipFileInfo alloc] init];
        info.name = data ? name : nil;      // name==nil => skip file
        info.data = data;
        info.date = [NSDate date];
        return info;
    }];
}


@end