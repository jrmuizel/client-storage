/**
 * clang++ main.mm -framework Cocoa -framework OpenGL -o test && ./test
 **/

#define TEXTURE_COUNT           5
#define TEXTURE_WIDTH           1024
#define TEXTURE_HEIGHT          768

#import <Cocoa/Cocoa.h>
#include <OpenGL/gl.h>

@interface TestView: NSView
{
  NSOpenGLContext* mContext;
  GLuint mProgramID;
  GLuint mTexture;
  GLuint mTextureUniform;
  GLuint mPosAttribute;
  GLuint mVertexbuffer;

  GLuint texIds[TEXTURE_COUNT];

  BOOL usePBO;
  GLuint pboIds[TEXTURE_COUNT];

  GLubyte *data;  GLubyte *data_bak;

  GLfloat rot;

}

@end

int tex_offset = 0;

@implementation TestView

- (id)initWithFrame:(NSRect)aFrame
{
  if (self = [super initWithFrame:aFrame]) {
    NSOpenGLPixelFormatAttribute attribs[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        (NSOpenGLPixelFormatAttribute)nil 
    };
    NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];
    mContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
    // Synchronize buffer swaps with vertical refresh rate
    GLint swapInt = 1;
    [mContext setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    GLint opaque = 1;
    [mContext setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    [mContext makeCurrentContext];
    [self _initGL];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_surfaceNeedsUpdate:)
                                                 name:NSViewGlobalFrameDidChangeNotification
                                               object:self];
  }
  return self;
}

- (void)dealloc
{
  [self _cleanupGL];
  [mContext release];
  [super dealloc];
}

static GLuint
CompileShaders(const char* vertexShader, const char* fragmentShader)
{
  // Create the shaders
  GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
  GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);

  GLint result = GL_FALSE;
  int infoLogLength;

  // Compile Vertex Shader
  glShaderSource(vertexShaderID, 1, &vertexShader , NULL);
  glCompileShader(vertexShaderID);

  // Check Vertex Shader
  glGetShaderiv(vertexShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(vertexShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* vertexShaderErrorMessage = new char[infoLogLength+1];
    glGetShaderInfoLog(vertexShaderID, infoLogLength, NULL, vertexShaderErrorMessage);
    printf("%s\n", vertexShaderErrorMessage);
    delete[] vertexShaderErrorMessage;
  }

  // Compile Fragment Shader
  glShaderSource(fragmentShaderID, 1, &fragmentShader , NULL);
  glCompileShader(fragmentShaderID);

  // Check Fragment Shader
  glGetShaderiv(fragmentShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(fragmentShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* fragmentShaderErrorMessage = new char[infoLogLength+1];
    glGetShaderInfoLog(fragmentShaderID, infoLogLength, NULL, fragmentShaderErrorMessage);
    printf("%s\n", fragmentShaderErrorMessage);
    delete[] fragmentShaderErrorMessage;
  }

  // Link the program
  GLuint programID = glCreateProgram();
  glAttachShader(programID, vertexShaderID);
  glAttachShader(programID, fragmentShaderID);
  glLinkProgram(programID);

  // Check the program
  glGetProgramiv(programID, GL_LINK_STATUS, &result);
  glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* programErrorMessage = new char[infoLogLength+1];
    glGetProgramInfoLog(programID, infoLogLength, NULL, programErrorMessage);
    printf("%s\n", programErrorMessage);
    delete[] programErrorMessage;
  }

  glDeleteShader(vertexShaderID);
  glDeleteShader(fragmentShaderID);

  return programID;
}

static GLuint
CreateTexture(NSSize size, void (^drawCallback)(CGContextRef ctx))
{
  int width = size.width;
  int height = size.height;
  CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
  CGContextRef imgCtx = CGBitmapContextCreate(NULL, width, height, 8, width * 4,
                                              rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(rgb);
  drawCallback(imgCtx);

  GLuint texture = 0;
  glActiveTexture(GL_TEXTURE0);
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, CGBitmapContextGetData(imgCtx));
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  return texture;
}

- (void)_initGL
{  
        // Create OpenGL textures
        if ([self initImageData])
                [self loadTexturesWithClientStorage];

        glEnable(GL_DEPTH_TEST);
        glEnableClientState(GL_VERTEX_ARRAY);
        glEnableClientState(GL_TEXTURE_COORD_ARRAY);
        [self invalidate];
}

- (void)_cleanupGL
{
  glDeleteTextures(1, &mTexture);
  glDeleteBuffers(1, &mVertexbuffer);
}

- (void)_surfaceNeedsUpdate:(NSNotification*)notification
{
  [mContext update];
}

- (void)invalidate
{
  //[self setNeedsDisplay:YES];
  [self performSelector:@selector(invalidate) withObject:nil afterDelay:0.0];
  [mContext setView:self];
  [mContext makeCurrentContext];

  NSSize backingSize = [self convertSizeToBacking:[self bounds].size];
  GLdouble width = backingSize.width;
  GLdouble height = backingSize.height;
  glViewport(0, 0, width, height);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  glOrtho(-1.0f, 1.0f, -1.0f, 1.0f, -10.0f, 10.0f);
  glMatrixMode(GL_MODELVIEW);
  

// Cube data
	const GLfloat vertices[6][12] = {
		{-1, 1,-1,  -1, 1, 1,  -1,-1, 1,  -1,-1,-1 }, //-x
		{ 1,-1,-1,   1,-1, 1,   1, 1, 1,   1, 1,-1 }, //+x
		{-1,-1,-1,  -1,-1, 1,   1,-1, 1,   1,-1,-1 }, //-y
		{ 1, 1,-1,   1, 1, 1,  -1, 1, 1,  -1, 1,-1 }, //+y
		{ 1,-1,-1,   1, 1,-1,  -1, 1,-1,  -1,-1,-1 }, //-z
		{-1,-1, 1,  -1, 1, 1,   1, 1, 1,   1,-1, 1 }, //+z
	};
	
	// Rectangle textures require non-normalized texture coordinates
	const GLfloat texcoords[] = {
		0,				0,
		0,				TEXTURE_HEIGHT,
		TEXTURE_WIDTH,	TEXTURE_HEIGHT,
		TEXTURE_WIDTH,	0,
	};
	
	int f, t;
	
	//glDeleteTextures(TEXTURE_COUNT, texIds);
	//[self loadTexturesWithClientStorage];
	memcpy(data + TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 *  sizeof(GLubyte) * (tex_offset), data_bak, TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * TEXTURE_COUNT *  sizeof(GLubyte));

	[self reloadTexturesWithClientStorage];


	
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	
	glPushMatrix();
	glScalef(0.5f, 0.5f, 0.5f);
	glRotatef(rot, 1, 1, 0);
	glRotatef(rot, 0, 1, 0);
	rot += 0.8;
	
	glTexCoordPointer(2, GL_FLOAT, 0, texcoords);
	for (f = 0; f < 6; f++)
	{
		t = f % TEXTURE_COUNT;
		glBindTexture(GL_TEXTURE_RECTANGLE_EXT, texIds[t+tex_offset]);
		
		glVertexPointer(3, GL_FLOAT, 0, vertices[f]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	glPopMatrix();


	
	glBindTexture(GL_TEXTURE_RECTANGLE_EXT, 0);

	


	
	
  [mContext flushBuffer];
{ int color = 0xffffff00;
		for (int c = tex_offset; c < TEXTURE_COUNT+tex_offset; c++) {

			for (int w = 0; w < TEXTURE_WIDTH; w++) {
				for (int h = 0; h < TEXTURE_HEIGHT; h++) {

				((int32_t*)data)[w + h*TEXTURE_WIDTH + c * TEXTURE_WIDTH * TEXTURE_HEIGHT] = 0xffffff00;
			}
		}
	}
	}
        if (tex_offset == 0)
		tex_offset = TEXTURE_COUNT;
	else {
		tex_offset = 0;
	}


}

- (void)drawRect:(NSRect)aRect
{
}

- (BOOL)wantsBestResolutionOpenGLSurface
{
  return YES;
}




- (void) loadTexturesWithClientStorage
{
	int	i;
	
	glGenTextures(TEXTURE_COUNT *2, texIds);
	
	// Enable the rectangle texture extenstion
	glEnable(GL_TEXTURE_RECTANGLE_EXT);
	
	// Eliminate a data copy by the OpenGL driver using the Apple texture range extension along with the rectangle texture extension
	// This specifies an area of memory to be mapped for all the textures. It is useful for tiled or multiple textures in contiguous memory.
	glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * TEXTURE_COUNT *2, data);

	for (i = 0; i < TEXTURE_COUNT *2; i++)
	{
		// Bind the rectange texture
		glBindTexture(GL_TEXTURE_RECTANGLE_EXT, texIds[i]);
		
		// Set a CACHED or SHARED storage hint for requesting VRAM or AGP texturing respectively
		// GL_STORAGE_PRIVATE_APPLE is the default and specifies normal texturing path
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE , GL_STORAGE_CACHED_APPLE);
		
		// Eliminate a data copy by the OpenGL framework using the Apple client storage extension
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
		
		// Rectangle textures has its limitations compared to using POT textures, for example,
		// Rectangle textures can't use mipmap filtering
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		
		// Rectangle textures can't use the GL_REPEAT warp mode
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			
		glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
			
		// OpenGL likes the GL_BGRA + GL_UNSIGNED_INT_8_8_8_8_REV combination
		glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, TEXTURE_WIDTH, TEXTURE_HEIGHT, 0, 
					 GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, &data[TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * i]);
	}
	
	glBindTexture(GL_TEXTURE_RECTANGLE_EXT, 0);
}
- (void) reloadTexturesWithClientStorage
{
	int	i;
	
	
	for (i = 0; i < TEXTURE_COUNT; i++)
	{
		// Bind the rectange texture
		glBindTexture(GL_TEXTURE_RECTANGLE_EXT, texIds[i + tex_offset]);
		// Set a CACHED or SHARED storage hint for requesting VRAM or AGP texturing respectively
		// GL_STORAGE_PRIVATE_APPLE is the default and specifies normal texturing path
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE , GL_STORAGE_CACHED_APPLE);
		
		// Eliminate a data copy by the OpenGL framework using the Apple client storage extension
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
		
		// Rectangle textures has its limitations compared to using POT textures, for example,
		// Rectangle textures can't use mipmap filtering
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		
		// Rectangle textures can't use the GL_REPEAT warp mode
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
		glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
		// OpenGL likes the GL_BGRA + GL_UNSIGNED_INT_8_8_8_8_REV combination
		glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, TEXTURE_WIDTH, TEXTURE_HEIGHT, 
					 GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, &data[TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * (i+tex_offset)]);
	}
	
	glBindTexture(GL_TEXTURE_RECTANGLE_EXT, 0);
}

- (BOOL) getImageData:(GLubyte*)imageData fromPath:(NSString*)path
{
	NSUInteger				width, height;
	NSURL					*url = nil;
	CGImageSourceRef		src;
	CGImageRef				image;
	CGContextRef			context = nil;
	CGColorSpaceRef			colorSpace;
	
	url = [NSURL fileURLWithPath: path];
	src = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
	
	if (!src) {
		NSLog(@"No image");
		return NO;
	}
	
	image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
	CFRelease(src);
	
	width = CGImageGetWidth(image);
	height = CGImageGetHeight(image);
	
	colorSpace = CGColorSpaceCreateDeviceRGB();
	context = CGBitmapContextCreate(imageData, width, height, 8, 4 * width, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
	CGColorSpaceRelease(colorSpace);
	
	// Core Graphics referential is upside-down compared to OpenGL referential
	// Flip the Core Graphics context here
	// An alternative is to use flipped OpenGL texture coordinates when drawing textures
	CGContextTranslateCTM(context, 0.0, height);
	CGContextScaleCTM(context, 1.0, -1.0);
	
	// Set the blend mode to copy before drawing since the previous contents of memory aren't used. This avoids unnecessary blending.
	CGContextSetBlendMode(context, kCGBlendModeCopy);
	
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
	
	CGContextRelease(context);
	CGImageRelease(image);
	
	return YES;
}

- (BOOL) initImageData
{
	int i;
	
	// This holds the data of all textures
	data = (GLubyte*) calloc(TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * TEXTURE_COUNT * 2, sizeof(GLubyte));
	data_bak = (GLubyte*) calloc(TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * TEXTURE_COUNT * 2, sizeof(GLubyte));

	
	for (i = 0; i < TEXTURE_COUNT; i++)
	{
		NSString *path = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"%d", i] ofType:@"jpg"];
		
		if (!path) {
			NSLog(@"No valid path");
			return NO;
		}
		
		// Point to the current texture
		GLubyte *imageData = &data[TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * i];
		
		if (![self getImageData:imageData fromPath:path])
			return NO;
	}
	for (i = 0; i < TEXTURE_COUNT; i++)
	{
		NSString *path = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"%d", i] ofType:@"jpg"];
		
		if (!path) {
			NSLog(@"No valid path");
			return NO;
		}
		
		// Point to the current texture
		GLubyte *imageData = &data[TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * (i+TEXTURE_COUNT)];
		
		if (![self getImageData:imageData fromPath:path])
			return NO;
	}
	memcpy(data_bak, data, TEXTURE_WIDTH * TEXTURE_HEIGHT * 4 * TEXTURE_COUNT * 2 * sizeof(GLubyte));
	
	return YES;
}
@end


@interface TerminateOnClose : NSObject<NSWindowDelegate>
@end

@implementation TerminateOnClose
- (void)windowWillClose:(NSNotification*)notification
{
  [NSApp terminate:self];
}
@end

int
main (int argc, char **argv)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  int style = 
    NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;
  NSRect contentRect = NSMakeRect(400, 300, 600, 400);
  NSWindow* window = [[NSWindow alloc] initWithContentRect:contentRect
                                       styleMask:style
                                         backing:NSBackingStoreBuffered
                                           defer:NO];

  NSView* view = [[TestView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)];
    
  [window setContentView:view];
  [window setDelegate:[[TerminateOnClose alloc] autorelease]];
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:window];

  [NSApp run];

  [pool release];
  
  return 0;
}


