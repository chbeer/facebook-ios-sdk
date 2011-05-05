/*
 * Copyright 2010 Facebook
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0

 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/


#import "FBDialog.h"
#import "Facebook.h"

///////////////////////////////////////////////////////////////////////////////////////////////////
// global

static NSString* kDefaultTitle = @"Connect to Facebook";

static CGFloat kFacebookBlue[4] = {0.42578125, 0.515625, 0.703125, 1.0};
static CGFloat kBorderGray[4] = {0.3, 0.3, 0.3, 0.8};
static CGFloat kBorderBlack[4] = {0.3, 0.3, 0.3, 1};
static CGFloat kBorderBlue[4] = {0.23, 0.35, 0.6, 1.0};

static CGFloat kBorderWidth = 10;

///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation FBDialog

@synthesize delegate = _delegate,
            params   = _params;

///////////////////////////////////////////////////////////////////////////////////////////////////
// private

- (void)addRoundedRectToPath:(CGContextRef)context rect:(NSRect)rect radius:(float)radius {
  CGContextBeginPath(context);
  CGContextSaveGState(context);
    
  CGRect cgrect = NSRectToCGRect(rect);

  if (radius == 0) {
    CGContextTranslateCTM(context, NSMinX(rect), NSMinY(rect));
    CGContextAddRect(context, cgrect);
  } else {
    rect = NSOffsetRect(NSInsetRect(rect, 0.5, 0.5), 0.5, 0.5);
    CGContextTranslateCTM(context, NSMinX(rect)-0.5, NSMinY(rect)-0.5);
    CGContextScaleCTM(context, radius, radius);
    float fw = NSWidth(rect) / radius;
    float fh = NSHeight(rect) / radius;

    CGContextMoveToPoint(context, fw, fh/2);
    CGContextAddArcToPoint(context, fw, fh, fw/2, fh, 1);
    CGContextAddArcToPoint(context, 0, fh, 0, fh/2, 1);
    CGContextAddArcToPoint(context, 0, 0, fw/2, 0, 1);
    CGContextAddArcToPoint(context, fw, 0, fw, fh/2, 1);
  }

  CGContextClosePath(context);
  CGContextRestoreGState(context);
}

- (void)drawRect:(NSRect)rect fill:(const CGFloat*)fillColors radius:(CGFloat)radius {
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

  if (fillColors) {
    CGContextSaveGState(context);
    CGContextSetFillColor(context, fillColors);
    if (radius) {
      [self addRoundedRectToPath:context rect:rect radius:radius];
      CGContextFillPath(context);
    } else {
      CGContextFillRect(context, NSRectToCGRect(rect));
    }
    CGContextRestoreGState(context);
  }

  CGColorSpaceRelease(space);
}

- (void)strokeLines:(NSRect)rect stroke:(const CGFloat*)strokeColor {
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

  CGContextSaveGState(context);
  CGContextSetStrokeColorSpace(context, space);
  CGContextSetStrokeColor(context, strokeColor);
  CGContextSetLineWidth(context, 1.0);

  {
    CGPoint points[] = {{rect.origin.x+0.5, rect.origin.y-0.5},
      {rect.origin.x+rect.size.width, rect.origin.y-0.5}};
    CGContextStrokeLineSegments(context, points, 2);
  }
  {
    CGPoint points[] = {{rect.origin.x+0.5, rect.origin.y+rect.size.height-0.5},
      {rect.origin.x+rect.size.width-0.5, rect.origin.y+rect.size.height-0.5}};
    CGContextStrokeLineSegments(context, points, 2);
  }
  {
    CGPoint points[] = {{rect.origin.x+rect.size.width-0.5, rect.origin.y},
      {rect.origin.x+rect.size.width-0.5, rect.origin.y+rect.size.height}};
    CGContextStrokeLineSegments(context, points, 2);
  }
  {
    CGPoint points[] = {{rect.origin.x+0.5, rect.origin.y},
      {rect.origin.x+0.5, rect.origin.y+rect.size.height}};
    CGContextStrokeLineSegments(context, points, 2);
  }

  CGContextRestoreGState(context);

  CGColorSpaceRelease(space);
}

- (NSURL*)generateURL:(NSString*)baseURL params:(NSDictionary*)params {
  if (params) {
    NSMutableArray* pairs = [NSMutableArray array];
    for (NSString* key in params.keyEnumerator) {
      NSString* value = [params objectForKey:key];
      NSString* escaped_value = (NSString *)CFURLCreateStringByAddingPercentEscapes(
                                  NULL, /* allocator */
                                  (CFStringRef)value,
                                  NULL, /* charactersToLeaveUnescaped */
                                  (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                  kCFStringEncodingUTF8);

      [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, escaped_value]];
      [escaped_value release];
    }

    NSString* query = [pairs componentsJoinedByString:@"&"];
    NSString* url = [NSString stringWithFormat:@"%@?%@", baseURL, query];
    return [NSURL URLWithString:url];
  } else {
    return [NSURL URLWithString:baseURL];
  }
}

- (void)postDismissCleanup {
  [NSApp endSheet:self.window];
}

- (void)dismiss:(BOOL)animated {
  [self dialogWillDisappear];

  [_loadingURL release];
  _loadingURL = nil;

  [self postDismissCleanup];
}

- (void)cancel:(id)sender {
  [self dialogDidCancel:nil];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// NSObject

- (id) init
{
    self = [super initWithWindowNibName:@"FBDialog"];
    if (!self) return nil;
    
    // load NIB
    self.window;
    
    return self;
}

- (void)dealloc {
  [_webView setResourceLoadDelegate:nil];
  [_webView release];
  [_params release];
  [_serverURL release];
  [_spinner release];
  [_titleLabel release];
  [_iconView release];
  [_closeButton release];
  [_loadingURL release];
  [super dealloc];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// UIView
/*
- (void)drawRect:(NSRect)rect {
  NSRect grayRect = NSOffsetRect(rect, -0.5, -0.5);
  [self drawRect:grayRect fill:kBorderGray radius:10];

  NSRect headerRect = NSMakeRect(
    ceil(rect.origin.x + kBorderWidth), ceil(rect.origin.y + kBorderWidth),
    rect.size.width - kBorderWidth*2, _titleLabel.frame.size.height);
  [self drawRect:headerRect fill:kFacebookBlue radius:0];
  [self strokeLines:headerRect stroke:kBorderBlue];

  NSRect webRect = NSMakeRect(
    ceil(rect.origin.x + kBorderWidth), headerRect.origin.y + headerRect.size.height,
    rect.size.width - kBorderWidth*2, _webView.frame.size.height+1);
  [self strokeLines:webRect stroke:kBorderBlack];
}*/

///////////////////////////////////////////////////////////////////////////////////////////////////
// WebViewDelegate


// Used to indicate that we've started loading (so that we can update our progress indicator
// and status text field)
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    if( frame == [_webView mainFrame] ) {
//        [self startedLoading];
    }
}


// Used to indicate that we've finished loading (so that we can update our progress indicator
// and status text field)
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if( frame == [_webView mainFrame] ) {
        [_spinner stopAnimation:self];
        [_spinner setHidden:YES];
        
        self.title = [_webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    }
}

- (void) handleWebView:(WebView *)sender failWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    NSLog(@"EntryController: Failed load: %@",error);
    if( frame == [_webView mainFrame] ) {
        [_spinner stopAnimation:self];
        [_spinner setHidden:YES];
        
        // 102 == WebKitErrorFrameLoadInterruptedByPolicyChange
        if (!([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102)) {
            [self dismissWithError:error animated:YES];
        }
    }
}

// Used to indicate that we've encountered an error during loading (so that we can update our 
// progress indicator and status text field)
- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    [self handleWebView:sender failWithError:error forFrame:frame];
}
// Also used to indicate that we've encountered an error during loading (so that we can update our 
// progress indicator and status text field)
- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    [self handleWebView:sender failWithError:error forFrame:frame];
}

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation 
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
	NSURL* url = request.URL;
    WebNavigationType navigationType = [[actionInformation objectForKey:WebActionNavigationTypeKey] intValue];
    
    if ([url.scheme isEqualToString:@"fbconnect"]) {
        if ([[url.resourceSpecifier substringToIndex:8] isEqualToString:@"//cancel"]) {
            NSString * errorCode = [self getStringFromUrl:[url absoluteString] needle:@"error_code="];
            NSString * errorStr = [self getStringFromUrl:[url absoluteString] needle:@"error_msg="];
            if (errorCode) {
                NSDictionary * errorData = [NSDictionary dictionaryWithObject:errorStr forKey:@"error_msg"];
                NSError * error = [NSError errorWithDomain:@"facebookErrDomain"
                                                      code:[errorCode intValue]
                                                  userInfo:errorData];
                [self dismissWithError:error animated:YES];
            } else {
                [self dialogDidCancel:url];
            }
        } else {
            [self dialogDidSucceed:url];
        }
        [listener ignore];
    } else if ([_loadingURL isEqual:url]) {
        [listener use];
    } else if (navigationType == WebNavigationTypeLinkClicked) {
        if ([_delegate respondsToSelector:@selector(dialog:shouldOpenURLInExternalBrowser:)]) {
            if (![_delegate dialog:self shouldOpenURLInExternalBrowser:url]) {
                [listener ignore];
            }
        }
        
        [NSApp openURL:request.URL];
        [listener ignore];
    } else {
        [listener use];
    }
}


//////////////////////////////////////////////////////////////////////////////////////////////////
// public

/**
 * Find a specific parameter from the url
 */
- (NSString *) getStringFromUrl: (NSString*) url needle:(NSString *) needle {
  NSString * str = nil;
  NSRange start = [url rangeOfString:needle];
  if (start.location != NSNotFound) {
    NSRange end = [[url substringFromIndex:start.location+start.length] rangeOfString:@"&"];
    NSUInteger offset = start.location+start.length;
    str = end.location == NSNotFound
    ? [url substringFromIndex:offset]
    : [url substringWithRange:NSMakeRange(offset, end.location)];
    str = [str stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  }

  return str;
}

- (id)initWithURL: (NSString *) serverURL
           params: (NSMutableDictionary *) params
         delegate: (id <FBDialogDelegate>) delegate {

  self = [self init];
  _serverURL = [serverURL retain];
  _params = [params retain];
  _delegate = delegate;

  return self;
}

- (NSString*)title {
  return [_titleLabel stringValue];
}

- (void)setTitle:(NSString*)title {
  [_titleLabel setStringValue:title];
}

- (void)load {
  [self loadURL:_serverURL get:_params];
}

- (void)loadURL:(NSString*)url get:(NSDictionary*)getParams {

  [_loadingURL release];
  _loadingURL = [[self generateURL:url params:getParams] retain];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:_loadingURL];

  [[_webView mainFrame] loadRequest:request];
}

- (void)show {
  [self load];

  [_spinner startAnimation:self];
//  _spinner.center = _webView.center;

/*  UIWindow* window = [UIApplication sharedApplication].keyWindow;
  if (!window) {
    window = [[UIApplication sharedApplication].windows objectAtIndex:0];
  }

  _modalBackgroundView.frame = window.frame;
  [_modalBackgroundView addSubview:self];
  [window addSubview:_modalBackgroundView];

  [window addSubview:self];*/

  [self dialogWillAppear];
    
  [NSApp beginSheet: self.window
     modalForWindow: [NSApp mainWindow]
      modalDelegate: self
     didEndSelector: @selector(didEndSheet:returnCode:contextInfo:)
        contextInfo: nil];

}

- (void)dismissWithSuccess:(BOOL)success animated:(BOOL)animated {
  if (success) {
    if ([_delegate respondsToSelector:@selector(dialogDidComplete:)]) {
      [_delegate dialogDidComplete:self];
    }
  } else {
    if ([_delegate respondsToSelector:@selector(dialogDidNotComplete:)]) {
      [_delegate dialogDidNotComplete:self];
    }
  }

  [self dismiss:animated];
}

- (void)dismissWithError:(NSError*)error animated:(BOOL)animated {
  if ([_delegate respondsToSelector:@selector(dialog:didFailWithError:)]) {
    [_delegate dialog:self didFailWithError:error];
  }

  [self dismiss:animated];
}

- (void)dialogWillAppear {
}

- (void)dialogWillDisappear {
}

- (void)dialogDidSucceed:(NSURL *)url {

  if ([_delegate respondsToSelector:@selector(dialogCompleteWithUrl:)]) {
    [_delegate dialogCompleteWithUrl:url];
  }
  [self dismissWithSuccess:YES animated:YES];
}

- (void)dialogDidCancel:(NSURL *)url {
  if ([_delegate respondsToSelector:@selector(dialogDidNotCompleteWithUrl:)]) {
    [_delegate dialogDidNotCompleteWithUrl:url];
  }
  [self dismissWithSuccess:NO animated:YES];
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
}

@end
