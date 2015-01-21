# Raw-RGB-Data-To-Movie

An application may generate a sequence of images that are intended to be viewed as a movie, outside of that application. These images may be created by, say, a software 3D renderer , a procedural texture generator, etc. In a typical OS X application, these images may be in the form of a CGImage or NSImage. In such cases, there are a variety of approaches for dumping such objects to a movie. However, in some cases the image is stored simply as an array of RGB (or ARGB) values. This project demonstrates how to create a movie from a sequence of such "raw" (A)RGB data.

Please visit the [Code From Above blog post](http://codefromabove.com/2015/01/av-foundation-saving-a-sequence-of-raw-rgb-frames-to-a-movie/) for a discussion of this code.
