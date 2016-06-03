//
//  WebPImageView.m
//  ImageButter
//
//  Created by Dalton Cherry on 8/27/15.
//

#import "WebPImageView.h"
#import "WebPImageManager.h"

@interface WebPImageView ()

@property(nonatomic)BOOL animated;
@property(nonatomic)NSInteger urlSessionId;
@property(nonatomic)NSInteger iterationCount; //how times has the animation looped
@property(nonatomic, copy)NSString *context;
@property(nonatomic)NSInteger index;
@property(nonatomic)BOOL isClear;
@property(nonatomic)CGPoint offsetOrigin;
@property(nonatomic)CGFloat aspectScale;
@property(nonatomic)BOOL moveIndex;
@property(nonatomic)UIImage *prevImg;
@property(nonatomic)CADisplayLink *displayLink;
@end

@implementation LinkedWebPImageView

- (void)dealloc {
  [self.displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.image = [[WebPImage alloc] init];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayDidRefresh:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    self.backgroundColor = [UIColor clearColor];
    self.aspectScale = 1;
    self.loopCount = 0;
    self.displayLink.paused = YES;
    self.layer.contentsScale = [UIScreen mainScreen].scale;
    
  }
  return self;
}

- (void)displayDidRefresh:(CADisplayLink *)link {
  
  if (!self.animated || self.pause) {
    return; //stop any running animated
  }
  
  if (self.iterationCount >= self.loopCount && self.loopCount > 0) {
    return;
  }
  
  if (self.index > 0 && self.image.hasAlpha) {
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0.0);
    [self drawViewHierarchyInRect:self.bounds afterScreenUpdates:NO];
    UIImage * img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    self.prevImg = img;
  }
  
  if (self.index >= self.image.frames.count) {
    self.index = 0;
    self.prevImg = nil;
    self.iterationCount++;
    if (self.didFinishAnimation) {
      self.didFinishAnimation(self.iterationCount);
    }
    
    if (self.iterationCount >= self.loopCount && self.loopCount > 0) {
      self.index = self.image.frames.count-1;
      return;
    }
  }
  [self.layer setNeedsDisplay];
  
  self.moveIndex = YES;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
  [super setBackgroundColor:backgroundColor];
  CGFloat white = 0;
  CGFloat alpha = 0;
  [self.backgroundColor getWhite:&white alpha:&alpha];
  self.isClear = NO;
  if (alpha < 1) {
    self.isClear = YES;
  }
}

- (void)setLoadingView:(UIView<WebPImageViewProgressDelegate> *)loadingView {
  [_loadingView removeFromSuperview];
  _loadingView = loadingView;
  [self addSubview:loadingView];
}

- (void)setImage:(WebPImage *)image {
  _image.finishedDecode = nil; //don't care about the old image anymore
  _image = image;
  if (image) {
    if (!image.isDecoded) {
      self.loadingView.hidden = NO;
      [self.loadingView setProgress:0];
      __weak typeof(self) weakSelf = self;
      image.finishedDecode = ^(WebPImage *img) {
        [weakSelf startDisplay];
      };
      image.decodeProgress = ^(CGFloat pro) {
        [weakSelf.loadingView setProgress:pro];
      };
    } else {
      [self startDisplay];
    }
  } else {
    [self startDisplay];
  }
}

- (void)setUrl:(NSURL *)url {
  WebPImageManager *manager = [WebPImageManager sharedManager];
  if (_url) {
    [manager cancelImageForSession:self.urlSessionId url:_url];
  }
  _url = url;
  self.loadingView.hidden = NO;
  [self.loadingView setProgress:0];
  __weak typeof(self) weakSelf = self;
  self.urlSessionId = [manager imageForUrl:url progress:^(CGFloat pro) {
    [weakSelf.loadingView setProgress:pro];
  } finished:^(WebPImage *img) {
    weakSelf.image = img;
  }];
}

- (NSInteger)frameInterval:(NSInteger)displayDuration {
  return displayDuration*60/1000*2;
}

- (void)startDisplay {
  
  self.loadingView.hidden = YES;
  self.animated = NO;
  self.prevImg = nil;
  self.index = 0;
  self.iterationCount = 0;
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout];
  
  if (self.image.frames.count > 1) {
    
    WebPFrame *frame = self.image.frames[self.index];
    self.displayLink.frameInterval = [self frameInterval:frame.displayDuration];
    self.animated = YES;
    self.pause = NO;
  }
  [self.layer setNeedsDisplay];
  
}

- (CGSize)intrinsicContentSize {
  if (self) {
    return self.image.size;
  }
  return CGSizeZero;
}

- (void)newContext {
  static NSString *letters = @"abcdefghijklmnopqurstuvwxyz";
  NSMutableString *str = [NSMutableString new];
  for(int i = 0; i < 14; i++) {
    [str appendFormat:@"%c",[letters characterAtIndex:arc4random() % 14]];
  }
  self.context = [NSString stringWithFormat:@"%@",str];
}

-(void)layoutSubviews {
  [super layoutSubviews];
  UIEdgeInsets inset = self.loadingInset;
  self.loadingView.frame = CGRectMake(inset.left, inset.top, self.bounds.size.width-inset.right,
                                      self.bounds.size.height-inset.bottom);
  CGFloat width = self.image.size.width;
  CGFloat height = self.image.size.height;
  if (width > 0 && height > 0) {
    BOOL isGreaterWidth = (width > self.bounds.size.width);
    BOOL isGreaterHeight = (height > self.bounds.size.height);
    if (isGreaterWidth || isGreaterHeight) {
      CGFloat hScale = height/self.bounds.size.height;
      CGFloat wScale = width/self.bounds.size.width;
      if (wScale > hScale && isGreaterWidth) {
        height = (height/width)*self.bounds.size.width;
        width = self.bounds.size.width;
        self.aspectScale = self.image.size.width/width;
      } else {
        width = (width/height)*self.bounds.size.height;
        height = self.bounds.size.height;
        self.aspectScale = self.image.size.height/height;
      }
    } else {
      self.aspectScale = 1;
    }
    CGFloat x = (self.bounds.size.width - width)/2;
    CGFloat y = (self.bounds.size.height - height)/2;
    if (x < 0) {
      x = 0;
    }
    if (y < 0) {
      y = 0;
    }
    
    self.offsetOrigin = CGPointMake(x, y);
  }
}

- (void)setAspectScale:(CGFloat)aspectScale {
  if (_aspectScale != aspectScale && !self.animated) {
    [self.layer setNeedsDisplay];
  }
  _aspectScale = aspectScale;
}

- (void)setPause:(BOOL)pause {
  _pause = pause;
  if(!pause) {
    if (self.index >= self.image.frames.count) {
      self.index = self.image.frames.count-1;
    }
  }
  self.displayLink.paused = pause;
}

- (CGFloat)aspect {
  return self.aspectScale;
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
  
  if (self.image.frames.count == 0) {
    return;
  }
  
  CGContextSetFillColorWithColor(ctx, self.backgroundColor.CGColor);
  
  if (self.prevImg) {
    UIGraphicsPushContext(ctx);
    [self.prevImg drawInRect:self.bounds];
    UIGraphicsPopContext();
  }
  
  if (self.index > 0 && self.index < self.image.frames.count) {
    WebPFrame *prevFrame = self.image.frames[self.index-1];
    if (prevFrame.dispose) {
      CGRect imgFrame = CGRectMake(self.offsetOrigin.x + (prevFrame.frame.origin.x/self.aspectScale),
                                   self.offsetOrigin.y + (prevFrame.frame.origin.y/self.aspectScale),
                                   prevFrame.frame.size.width/self.aspectScale, prevFrame.frame.size.height/self.aspectScale);
      if (self.isClear) {
        CGContextClearRect(ctx, imgFrame);
      } else {
        CGContextFillRect(ctx, imgFrame);
      }
    }
  }
  
  if(self.index > -1 && self.index < _image.frames.count) {
    WebPFrame *frame = self.image.frames[self.index];
    CGRect imgFrame = CGRectMake(self.offsetOrigin.x + (frame.frame.origin.x/self.aspectScale),
                                 self.offsetOrigin.y + (frame.frame.origin.y/self.aspectScale),
                                 frame.frame.size.width/self.aspectScale, frame.frame.size.height/self.aspectScale);
    if (!frame.blend) {
      if (self.isClear) {
        CGContextClearRect(ctx, imgFrame);
      } else {
        CGContextFillRect(ctx, imgFrame);
      }
    }
    
    UIGraphicsPushContext(ctx);
    [frame.image drawInRect:imgFrame];
    UIGraphicsPopContext();
    
    if (self.moveIndex) {
      self.index++;
      self.moveIndex = NO;
    }
  }
}

@end
