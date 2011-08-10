/*=========================================================================
 
 Program:   Visualization Toolkit
 Module:    EAGLView.mm
 
 Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
 All rights reserved.
 See Copyright.txt or http://www.kitware.com/Copyright.htm for details.
 
 This software is distributed WITHOUT ANY WARRANTY; without even
 the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 PURPOSE.  See the above copyright notice for more information.
 
 =========================================================================*/

#import "EAGLView.h"
#import "ES2Renderer.h"

#import "vesCamera.h"
#import "vesRenderer.h"

#define USE_DEPTH_BUFFER 1

@interface kwGestureDelegate : NSObject <UIGestureRecognizerDelegate>{
  
}
@end

@implementation kwGestureDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  BOOL rotating2D = 
  [gestureRecognizer isMemberOfClass:[UIRotationGestureRecognizer class]] ||
  [otherGestureRecognizer isMemberOfClass:[UIRotationGestureRecognizer class]];
  
  BOOL pinching = 
  [gestureRecognizer isMemberOfClass:[UIPinchGestureRecognizer class]] ||
  [otherGestureRecognizer isMemberOfClass:[UIPinchGestureRecognizer class]];
  
  BOOL panning = 
  [gestureRecognizer numberOfTouches] == 2 &&
  ([gestureRecognizer isMemberOfClass:[UIPanGestureRecognizer class]] ||
   [otherGestureRecognizer isMemberOfClass:[UIPanGestureRecognizer class]]);
  
  if ((pinching && panning) ||
      (pinching && rotating2D) ||
      (panning && rotating2D))
  {
    return YES;
  }
  return NO;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
  return YES;
}
@end

@interface EAGLView ()
@property (nonatomic, retain) EAGLContext *context;

- (BOOL) createFramebuffer;
- (void) destroyFramebuffer;


@end

@implementation EAGLView

@synthesize context;

// You must implement this method
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

//The EAGL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder
{    
  self = [super initWithCoder:coder];
  if (self)
  {
    // Get the layer
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    
    eaglLayer.opaque = TRUE;
    eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!context || ![EAGLContext setCurrentContext:context])
        {
          [self release];
          return nil;
        }
    

    renderer = [[ES2Renderer alloc] init];
    
    if (!renderer)
    {
			[self release];
			return nil;
    }

    [self createGestureRecognizers];
    self.multipleTouchEnabled = YES;
  }
  
  return self;
}

- (void)layoutSubviews 
{
  [EAGLContext setCurrentContext:context];
  [self destroyFramebuffer];
  [self createFramebuffer];
  [renderer resizeFromLayer:backingWidth height:backingHeight];
  [self drawView:nil];
}

- (BOOL)createFramebuffer 
{  
  glGenFramebuffers(1, &viewFramebuffer);
  glGenRenderbuffers(1, &viewRenderbuffer);
  
  glBindFramebuffer(GL_FRAMEBUFFER, viewFramebuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
  [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, viewRenderbuffer);
  
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
  
  if (USE_DEPTH_BUFFER) {
    glGenRenderbuffers(1, &depthRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
  }
  
  if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    return NO;
  }
  
  return YES;
}


- (void)destroyFramebuffer 
{  
  glDeleteFramebuffers(1, &viewFramebuffer);
  viewFramebuffer = 0;
  glDeleteRenderbuffers(1, &viewRenderbuffer);
  viewRenderbuffer = 0;
  
  if(depthRenderbuffer) {
    glDeleteRenderbuffers(1, &depthRenderbuffer);
    depthRenderbuffer = 0;
  }
}

- (void)drawView:(id) sender {  
  [EAGLContext setCurrentContext:context];
  glBindFramebuffer(GL_FRAMEBUFFER, viewFramebuffer);
  glViewport(0, 0, backingWidth, backingHeight);
  [renderer render];
  glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
  [context presentRenderbuffer:GL_RENDERBUFFER];
}


- (void)dealloc
{
  if ([EAGLContext currentContext] == context)
    [EAGLContext setCurrentContext:nil];
	
  [context release];
  context = nil;
  [renderer release];
  [super dealloc];
}

- (void)resetView
{
  [self stopInertialMotion]; 
  [renderer resetView];
  [self drawView:nil];
}

- (void) setFilePath :(NSString *) fpath
{
	if(renderer){
		[renderer setFilePath:fpath];
    [self resetView];
	}
}


#pragma mark -
#pragma mark Touch handling

- (void) createGestureRecognizers
{
  UIPanGestureRecognizer *singleFingerPanGesture = [[UIPanGestureRecognizer alloc]
                                                    initWithTarget:self action:@selector(handleSingleFingerPanGesture:)];
  singleFingerPanGesture.maximumNumberOfTouches = 1;
  singleFingerPanGesture.minimumNumberOfTouches = 1;
  [self addGestureRecognizer:singleFingerPanGesture];
  [singleFingerPanGesture release];
  
  UIPanGestureRecognizer *doubleFingerPanGesture = [[UIPanGestureRecognizer alloc]
                                                    initWithTarget:self action:@selector(handleDoubleFingerPanGesture:)];
  doubleFingerPanGesture.maximumNumberOfTouches = 2;
  doubleFingerPanGesture.minimumNumberOfTouches = 2;
  [self addGestureRecognizer:doubleFingerPanGesture];
  [doubleFingerPanGesture release];
  
  UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc]
                                            initWithTarget:self action:@selector(handlePinchGesture:)];
  [self addGestureRecognizer:pinchGesture];
  [pinchGesture release];
  
  UIRotationGestureRecognizer *rotate2DGesture = [[UIRotationGestureRecognizer alloc]
                                                  initWithTarget:self action:@selector(handle2DRotationGesture:)];
  [self addGestureRecognizer:rotate2DGesture];
  [rotate2DGesture release];
  
  UIRotationGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(handleTapGesture:)];
  // this is needed so that the buttons on top of the render view will 
  // work since this is the first responder---is this the best way to 
  // fix this problem?
  tapGesture.cancelsTouchesInView = NO;
  [self addGestureRecognizer:tapGesture];
  [tapGesture release];
  
  //
  // allow two-finger gestures to work simultaneously
  kwGestureDelegate* gestureDelegate = [[kwGestureDelegate alloc] init];
  [rotate2DGesture setDelegate:gestureDelegate];
  [pinchGesture setDelegate:gestureDelegate];
  [doubleFingerPanGesture setDelegate:gestureDelegate];
}

- (IBAction)handleDoubleFingerPanGesture:(UIPanGestureRecognizer *)sender
{
  if (sender.state == UIGestureRecognizerStateEnded ||
      sender.state == UIGestureRecognizerStateCancelled)
  {
    // start inertial pan?
    return;
  }
  
  if (sender.state == UIGestureRecognizerStateBegan)
  {
    [self stopInertialMotion];
  }
  
  //
  // get current translation and (then zero it out so it won't accumulate)
  CGPoint currentLocation = [sender locationInView:self];
  CGPoint currentTranslation = [sender translationInView:self];
  [sender setTranslation:CGPointZero inView:self];
  
  //
  // compute the previous location (have to flip y)
  CGPoint previousLocation;
  previousLocation.x = currentLocation.x - currentTranslation.x;
  previousLocation.y = currentLocation.y + currentTranslation.y;
  
  //
  // calculate the focal depth so we'll know how far to move
  vesRenderer* ren = [self->renderer getRenderer];
  vesCamera* camera = ren->GetCamera();
  vesVector3f viewFocus = camera->GetFocalPoint();
  vesVector3f viewFocusDisplay = ren->ComputeWorldToDisplay(viewFocus);
  float focalDepth = viewFocusDisplay[2];
  
  //
  // map change into world coordinates
  vesVector3f newPickPoint = ren->ComputeDisplayToWorld(vesVector3f(currentLocation.x,
                                                                    currentLocation.y,
                                                                    focalDepth));
  vesVector3f oldPickPoint = ren->ComputeDisplayToWorld(vesVector3f(previousLocation.x,
                                                                    previousLocation.y,
                                                                    focalDepth));
  
  vesVector3f motionVector = oldPickPoint - newPickPoint;
  
  vesVector3f viewPoint = camera->GetPosition();
  vesVector3f newViewFocus = motionVector + viewFocus;
  vesVector3f newViewPoint = motionVector + viewPoint;
  camera->SetFocalPoint(newViewFocus);
  camera->SetPosition(newViewPoint);
  // simultaneious with pinch temporarily remove draw request
  // evenutally this should be a "schedule render" and not a 
  // "force render" call
  //[self drawView:nil];
}

- (IBAction)handleSingleFingerPanGesture:(UIPanGestureRecognizer *)sender
{ 
  if (sender.state == UIGestureRecognizerStateEnded ||
      sender.state == UIGestureRecognizerStateCancelled)
  {
    if (lastRotationMotionNorm > 4.0f)
    {
      self->inertialRotationThread = [[NSThread alloc] initWithTarget:self selector:@selector(handleInertialRotation) object:nil];
      [inertialRotationThread start];
    }
    return;
  }
  
  if (sender.state == UIGestureRecognizerStateBegan)
  {
    [self stopInertialMotion];
  }
  
  //
  // get current translation and (then zero it out so it won't accumulate)
  CGPoint currentTranslation = [sender translationInView:self];
  [sender setTranslation:CGPointZero inView:self];
  
  // 
  // update data for inertial rotation
  self->lastRotationMotionNorm = sqrtf(currentTranslation.x*currentTranslation.x + 
                                       currentTranslation.y*currentTranslation.y);
  if (self->lastRotationMotionNorm > 0)
  {
    self->lastMovementXYUnitDelta.x = currentTranslation.x / lastRotationMotionNorm;
    self->lastMovementXYUnitDelta.y = currentTranslation.y / lastRotationMotionNorm;
    
    //
    // apply the rotation and rerender
    [self rotate:currentTranslation];
    [self drawView:nil];
  }
  else
  {
    self->lastMovementXYUnitDelta.x = 0.0f;
    self->lastMovementXYUnitDelta.y = 0.0f;
  }
}

- (IBAction)handlePinchGesture:(UIPinchGestureRecognizer *)sender
{  
  if (sender.state == UIGestureRecognizerStateEnded ||
      sender.state == UIGestureRecognizerStateCancelled)
  {
    return;
  }
  
  if (sender.state == UIGestureRecognizerStateBegan)
  {
    [self stopInertialMotion];
  }
  
  //
  // apply dolly
  vesRenderer* ren = [self->renderer getRenderer];
  vesCamera* camera = ren->GetCamera();
  camera->Dolly(sender.scale);
  
  //
  // reset scale so it won't accumulate
  sender.scale = 1.0;
  
  [self drawView:nil];
}

- (IBAction)handle2DRotationGesture:(UIRotationGestureRecognizer *)sender
{  
  if (sender.state == UIGestureRecognizerStateEnded ||
      sender.state == UIGestureRecognizerStateCancelled)
  {
    return;
  }
  
  if (sender.state == UIGestureRecognizerStateBegan)
  {
    [self stopInertialMotion];
  }
  
  //
  // apply roll
  vesRenderer* ren = [self->renderer getRenderer];
  vesCamera* camera = ren->GetCamera();
  camera->Roll(sender.rotation * 180.0 / M_PI);
  camera->OrthogonalizeViewUp();
  
  //
  // reset rotation so it won't accumulate
  [sender setRotation:0.0];
  
  // simultaneious with pinch temporarily remove draw request
  // evenutally this should be a "schedule render" and not a 
  // "force render" call
  //[self drawView:nil];
}

- (IBAction)handleTapGesture:(UITapGestureRecognizer *)sender
{ 
  [self stopInertialMotion];
}

- (void)rotate: (CGPoint)delta
{
  //
  // Rotate camera
  // Based on vtkInteractionStyleTrackballCamera::Rotate().
  //
  
  vesRenderer* ren = [self->renderer getRenderer];
  
  double delta_elevation = -20.0 / ren->GetHeight();
  double delta_azimuth = -20.0 / ren->GetWidth();
  double motionFactor = 10.0;
  
  double rxf = delta.x * delta_azimuth * motionFactor;
  double ryf = delta.y * delta_elevation * motionFactor;
  
  vesCamera *camera = [self->renderer getRenderer]->GetCamera();
  camera->Azimuth(rxf);
  camera->Elevation(ryf);
  camera->OrthogonalizeViewUp();  
}

- (void)handleInertialRotation
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  CGPoint delta;
  while (lastRotationMotionNorm > 0.5)
  {
    [NSThread sleepForTimeInterval:1/30.0];
    
    if ([[NSThread currentThread] isCancelled])
    {
      break;
    }
    
    delta.x = lastRotationMotionNorm*lastMovementXYUnitDelta.x;
    delta.y = lastRotationMotionNorm*lastMovementXYUnitDelta.y;
    [self rotate:delta];
    
    [self drawView:nil];
    lastRotationMotionNorm *= 0.9;
  }
  lastRotationMotionNorm = 0;
  [pool release];
  //[NSThread exit];
}

- (void) stopInertialMotion
{
  if (inertialRotationThread)
  {
    [inertialRotationThread setThreadPriority:1.0f];
    [inertialRotationThread cancel];
    
    // TODO: something is wrong with this implementation so there is a hack here. 
    // This busy wait is causing a jerky stop to the inertial rotation so I'm setting the 
    // priorty of the inertia thread up high and pausing here a bit so that it can finish 
    // its render.  The priority and sleep should be removed when the wait is improved
    [NSThread sleepForTimeInterval:1/20.0];
    while (![inertialRotationThread isFinished])
    {
      // busy wait for the thread to exit
    }
    [inertialRotationThread release];
    inertialRotationThread = nil;
  }
}

#pragma mark -
#pragma mark Model information


-(int) getNumberOfFacetsForCurrentModel
{
  if (renderer)
  {
    return [renderer getNumberOfFacetsForCurrentModel];
  }
  return 0;
}

-(int) getNumberOfLinesForCurrentModel
{
  if (renderer)
  {
    return [renderer getNumberOfLinesForCurrentModel];
  }
  return 0;
}


-(int) getNumberOfVerticesForCurrentModel
{
  if (renderer)
  {
    return [renderer getNumberOfVerticesForCurrentModel];
  }
  return 0;
}



@end
