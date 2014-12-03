# math3d.js

A simple javascript library for creating interactive plots built on top of
three.js.

# API Reference

Once included, math3d.js introduces a single global function `math3d` which
takes a single object argument of the following form:

```javascript
{
    scene       : required, // an object describing the scene to plot (see below) or a url pointing to a JSON string that parses to such an object
    element     : required, // a DOM element to attach the plot to
    timeout     : 30000,    // number of milleseconds to wait before timing out fetchs
    callback    : null,     // optional callback taking arguments (scene object, error)
}
```

A scene object has two properties:
```javascript
{
    obj : required, // object to plot, e.g. sphere, point, line, etc. see below

    opts    : { // global options for the scene

        width   : 1/2*clientWidth,  // width of the scene in pixels
        height  : 2/3*width,        // height of the scene in pixels

        renderer    : best guess,   // either 'webgl' or 'canvas'

        background  : [1, 1, 1],    // background color in RGB

        aspect_ratio    : [1, 1, 1],    // a list [a, b, c] of length 3, which
                                        // scales the x, y, z coordinates of
                                        // everything by the given values

        fast_points : false,    // if true, will use a faster point
                                // implementation, but they will be square and
                                // will only work with the webgl renderer

        frame   : { // options for the frame

            thickness   : .4,   // thickness of the frame (zero thickness
                                // disables the frame)

            color   : -background,  // color of the frame

            labels  : true, // whether or not to enable labels on the frame

            fontface    : helvetiker,   // font of the labels
        },

        light   : { // options for the light

            color   : [1, 1, 1],    // color of the scene's light

            intensity   : 0.75, // intensity of camera's light (on a scale
                                // of 0 to 1)
        },
    },
}
```

## Math3d objects

Every math3d object (with the exception of groups) must have the following
common properties:

```javascript
{
    type    : required, // specify the type of math3d object (e.g. 'sphere')

    texture : required, // specify the texture or material of the object
                        // (which is again an object)
}
```

A texture specifies the color, transparency, etc of the object. Specifically,
it consists of the following attributes:

```javascript
{
    color   : required, // RGB color (e.g. [0.1, 0.2, 0.3])

    ambient : required, // ambient RGB color

    specular    : required, // specular RGB color

    opacity : required, // opacity on a scale of 0 to 1
}
```

### Groups

Groups are special, they allow you to include multiple objects
in a single scene. Like other math3d objects, you must specify
their type (in this case their type is `'group'`), however
unlike all other objects, a texture is not needed. Groups
look like the following:

```javascript
{
    type    : 'group',

    subobjs : required, // a list of math3d objects
}
```

### Lines

Lines have the following options:

```javascript
{
    type    : 'line',
    texture : required,

    points  : required, // a list of points the line will traverse (e.g.
                        // [[0,1,2],[3,4,5],[6,7,8]] will create a line that
                        // starts at [0,1,2], moves on to [3,4,5] and then
                        // ends at [6,7,8]

    thickness : 1,  // how thick the line should be
}
```

### Points

Points have the following options:

```javascript
{
    type    : 'point',
    texture : required,

    loc : required, // location of the point

    size    : 5,    // size of the point
}
```

### Text

Text has the following options:

```javascript
{
    type    : 'text',
    texture : required,

    text    : required, // the text that should be displayed

    loc : required, // location for the center of the text

    rotation    : face the camera,  // rotation as Euler angles,

    size    : 1,   // size of the text
}
```

### Sphere

Spheres have the following options:

```javascript
{
    type    : 'sphere',
    texture : required,

    loc : required, // location of the center of the sphere

    radius  : 5,    // radius of the sphere
}
```

### Torus

Tori have the following options:

```javascript
{
    type    : 'torus',
    texture : required,

    loc : required, // location of the center of the torus

    inner_radius  : 0.3,    // inner radius of the torus
    outer_radius  : 1,      // outer radius of the torus
}
```

### Index Face Set

Index face sets have the following options:

```javascript
{
    type    : 'index_face_set',
    texture : required,

    vertices    : required, // a list of vertices that may be used
                            // for the faces

    faces   : required,     // a list of lists, where each inner list is a
                            // sequence of indices of the vertex list which
                            // correspond to a vertex of the face (e.g. if
                            // vertices = [[0,0,0],[1,1,1],[0,1,0],[1,0,0]],
                            // and faces = [[0,1,2],[1,2,3]] would represent
                            // the triangles [0,0,0],[1,1,1],[0,1,0] and
                            // [1,1,1],[0,1,0],[1,0,0])
                            // the vertices of a face are assumed to coplanar,
                            // convex, and listed in either clockwise, or
                            // counter-clockwise order

    wireframe   : false, // if true, only draws a wireframe version
}
```
