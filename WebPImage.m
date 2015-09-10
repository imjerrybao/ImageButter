//
//  WPImage.m
//  WebPObjc
//
//  Created by Dalton Cherry on 8/27/15.
//

#import "WebPImage.h"
#import <WebP/decode.h>
#import <WebP/demux.h>
#import "WebPImageManager.h"

static void free_image_data(void *info, const void *data, size_t size) {
    free((void *)data);
}

@implementation WebPImage

- (instancetype)initWithData:(NSData*)data {
    if(self = [super init]) {
        [self decode:data];
        _isDecoded = YES;
    }
    return self;
}

- (instancetype)initWithData:(NSData*)data async:(WebPDecodeFinished)finished {
    if(self = [super init]) {
        _isDecoded = NO;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
            [self decode:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                _isDecoded = YES;
                if(finished) {
                    finished(weakSelf);
                }
                if(self.finishedDecode) {
                    self.finishedDecode(weakSelf);
                }
            });
        });
    }
    return self;
}

- (void)decode:(NSData*)data {
    NSMutableArray *collect = [NSMutableArray array];
    WebPData webpData;
    WebPDataInit(&webpData);
    webpData.bytes = (const uint8_t *)[data bytes];
    webpData.size = [data length];
    CGFloat scale = [[UIScreen mainScreen] scale];
    
    // setup the demux we need for animated webp images.
    WebPDemuxer* demux = WebPDemux(&webpData);
    uint32_t flags = WebPDemuxGetI(demux, WEBP_FF_FORMAT_FLAGS); // get the feature flags from the webp data.
    uint32_t canvasWidth = WebPDemuxGetI(demux, WEBP_FF_CANVAS_WIDTH)/scale;
    uint32_t canvasHeight = WebPDemuxGetI(demux, WEBP_FF_CANVAS_HEIGHT)/scale;
    uint32_t frameCount = WebPDemuxGetI(demux, WEBP_FF_FRAME_COUNT);
    //uint32_t loopCount = WebPDemuxGetI(demux, WEBP_FF_LOOP_COUNT);
    uint32_t backgroundColor = WebPDemuxGetI(demux, WEBP_FF_BACKGROUND_COLOR);
    int b = (backgroundColor >> 24) & 0xff;  // high-order (leftmost) byte: bits 24-31
    int g = (backgroundColor >> 16) & 0xff;  // next byte, counting from left: bits 16-23
    int r = (backgroundColor >>  8) & 0xff;  // next byte, bits 8-15
    int a = backgroundColor         & 0xff;  // low-order byte: bits 0-7
    _backgroundColor = [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a/255.0f];
    _size = CGSizeMake(canvasWidth, canvasHeight);
    // setup the config. Probably need this to be customizable.
    WebPDecoderConfig config;
    WebPInitDecoderConfig(&config);
    //config.options.no_fancy_upsampling = 1;
    //config.options.bypass_filtering = 1;
    config.options.use_threads = 1;
    //config.options.use_scaling = 1;
    CGFloat progressOffset = 1/(CGFloat)frameCount;
    CGFloat progress = 0;
    if(flags & ANIMATION_FLAG) { // check if our features include animation. We could also just query the num of frames from the iterator.
        //int index = 0;
        WebPIterator iter; // that would like this iter.num_frames > 1
        if (WebPDemuxGetFrame(demux, 1, &iter)) { // init the iter and get the first frame.
            do {
                WebPData frame = iter.fragment;
                UIImage *image = [self createImage:frame.bytes size:frame.size config:&config scale:scale];
                if(image) {
                    NSInteger duration = iter.duration;
                    NSLog(@"duration: %d",iter.duration);
                    if(duration <= 0) {
                        duration = 100;
                    }
                    BOOL blend = (iter.blend_method == WEBP_MUX_BLEND);
                    BOOL dispose = (iter.dispose_method == WEBP_MUX_DISPOSE_BACKGROUND);
                    CGRect frame = CGRectMake(iter.x_offset/scale, iter.y_offset/scale,
                                              iter.width/scale, iter.height/scale);
                    [collect addObject:[[WebPFrame alloc] initWithFrame:frame image:image
                                                              dispose:dispose blend:blend
                                                             duration:duration]];
                    progress += progressOffset;
                    [self updateProgress:progress];
                }
            } while(WebPDemuxNextFrame(&iter));
            
            WebPDemuxReleaseIterator(&iter);
        }
    } else {
        UIImage *image = [self createImage:webpData.bytes size:webpData.size config:&config scale:scale];
        if(image) {
            [collect addObject:[[WebPFrame alloc] initWithFrame:
                                CGRectMake(0, 0, image.size.width, image.size.height)
                                                        image:image dispose:YES blend:NO duration:0]];
            progress += progressOffset;
            [self updateProgress:progress];
        }
    }
    
    WebPDemuxDelete(demux);
    _frames = collect;
}

- (void)updateProgress:(CGFloat)progress {
    if(progress > 1) {
        progress = 1;
    } else if(progress < 0) {
        progress = 0;
    }
    if(self.decodeProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.decodeProgress(progress);
        });
    }
}

- (UIImage *)createImage:(const uint8_t *)bytes size:(size_t)size config:(WebPDecoderConfig *)config scale:(CGFloat)scale {
    if(WebPDecode(bytes, size, config) != VP8_STATUS_OK) {
        return nil;
    }
    //NSLog(@"output width: %d height: %d",config->output.width, config->output.height);
    int width, height = 0;
    uint8_t *data = WebPDecodeRGBA(bytes, size, &width, &height);
    // Construct a UIImage from the decoded RGBA value array
    CGDataProviderRef provider = CGDataProviderCreateWithData(&config, data, width * height * 4, free_image_data);
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGImageRef imageRef = CGImageCreate(width, height, 8, 32, 4 * width,
                                        colorSpaceRef, kCGBitmapByteOrderDefault | kCGImageAlphaLast,
                                        provider, NULL, YES, kCGRenderingIntentDefault);
    UIImage *image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
    
    // Clean the UIImage we just created.
    CGImageRelease(imageRef);
    CGColorSpaceRelease(colorSpaceRef);
    CGDataProviderRelease(provider);
    WebPFreeDecBuffer(&config->output);
    
    return image;
}

@end

#pragma mark - WebPFrame implementation 

@implementation WebPFrame

- (instancetype)initWithFrame:(CGRect)frame image:(UIImage*)image dispose:(BOOL)dispose blend:(BOOL)blend duration:(NSInteger)duration {
    if(self = [super init]) {
        _frame = frame;
        _image = image;
        _dispose = dispose;
        _blend = blend;
        _displayDuration = duration;
    }
    return self;
}

@end
