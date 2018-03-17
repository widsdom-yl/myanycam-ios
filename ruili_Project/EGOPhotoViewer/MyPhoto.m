//
//  MyPhoto.m
//  EGOPhotoViewerDemo_iPad
//
//  Created by Devin Doty on 7/3/10July3.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "MyPhoto.h"

@implementation MyPhoto

@synthesize URL=_URL;
@synthesize caption=_caption;
@synthesize image=_image;
@synthesize size=_size;
@synthesize failed=_failed;
@synthesize imagePath = _imagePath;
@synthesize proxyName = _proxyName;
@synthesize cellData = _cellData;

- (id)initWithImageURL:(NSURL*)aURL name:(NSString*)aName image:(UIImage*)aImage{
	
	if (self = [super init]) {
	
		_URL=[aURL retain];
		_caption=[aName retain];
		_image=[aImage retain];
		
	}
	
	return self;
}

- (id)initWithImageURL:(NSURL*)aURL name:(NSString*)aName{
    
	return [self initWithImageURL:aURL name:aName image:nil];
}

- (id)initWithImageURL:(NSURL*)aURL{
    
	return [self initWithImageURL:aURL name:nil image:nil];
}

- (id)initWithImage:(UIImage*)aImage{
    
	return [self initWithImageURL:nil name:nil image:aImage];
}

- (void)setImage:(UIImage *)image
{
    
    if (image != _image) {
        [_image release];
        _image = [image retain];
    }
    
}

- (void)dealloc{
	
	[_URL release], _URL=nil;
	[_image release], _image=nil;
	[_caption release], _caption=nil;
    self.imagePath = nil;
	self.proxyName = nil;
    self.cellData = nil;
	[super dealloc];
}


@end
