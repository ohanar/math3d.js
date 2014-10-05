###############################################################################
# Copyright (c) 2013, 2014, William Stein
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###############################################################################

if not document?
    document = window.document

math3d = (window.math3d ?= {})
        
trunc = (s, max_length) ->
    if not s?
        return s
    if not max_length?
        max_length = 1024
    if s.length > max_length
        s.slice(0, max_length-3) + "..."
    else
        s

# Returns a new object with properties determined by those of obj1 and
# obj2.  The properties in obj1 *must* all also appear in obj2.  If an
# obj2 property has value "defaults.required", then it must appear in
# obj1.  For each property P of obj2 not specified in obj1, the
# corresponding value obj1[P] is set (all in a new copy of obj1) to
# be obj2[P].
defaults = (obj1, obj2, allow_extra) ->
    if not obj1?
        obj1 = {}
    error = ->
        try
            s = "(obj1=#{trunc(JSON.stringify(obj1),1024)}, obj2=#{trunc(JSON.stringify(obj2),1024)})"
            #console.log s
            return s
        catch error
            return ""
    if typeof(obj1) isnt 'object'
        # We put explicit traces before the errors in this function,
        # since otherwise they can be very hard to debug.
        console.trace()
        throw "defaults -- TypeError: function takes inputs as an object #{error()}"
    r = {}
    for prop, val of obj2
        if obj1.hasOwnProperty(prop) and obj1[prop]?
            if obj2[prop] is defaults.required and not obj1[prop]?
                console.trace()
                throw "defaults -- TypeError: property '#{prop}' must be specified: #{error()}"
            r[prop] = obj1[prop]
        else if obj2[prop]?  # only record not undefined properties
            if obj2[prop] is defaults.required
                console.trace()
                throw "defaults -- TypeError: property '#{prop}' must be specified: #{error()}"
            else
                r[prop] = obj2[prop]
    if not allow_extra
        for prop, val of obj1
            if not obj2.hasOwnProperty prop
                console.trace()
                throw "defaults -- TypeError: got an unexpected argument '#{prop}' #{error()}"
    return r

# WARNING -- don't accidentally use this as a default:
required = defaults.required = "__!!!!!!this is a required property!!!!!!__"

component_to_hex = (c) ->
    hex = c.toString 16
    if hex.length is 1
        "0" + hex
    else
        hex

rgb_to_hex = (r, g, b) -> "#" + component_to_hex(r) + component_to_hex(g) + component_to_hex(b)

_loading_threejs_callbacks = []

math3d.threejs_src = "http://cdnjs.cloudflare.com/ajax/libs/three.js/r68/three.min.js"
math3d.orbitcontrols_src = "OrbitControls.js"

remove_element = (element) ->
    if element is null
        return
    if (parent = element.parentElement) is null
        return
    parent.removeChild element

loadScript = (script_src, callback) ->
    run_callback = true

    script = document.createElement 'script'
    script.type = 'text/javascript'
    script.async = true
    script.src = script_src

    script.onload = ->
            remove_element script
            if run_callback
                run_callback = false
                callback()
    script.onerror = ->
            remove_element script
            if run_callback
                run_callback = false
                callback "error loading script #{script.src}"

    document.head.appendChild script

load_threejs = (callback) ->
    if THREE?.Scene? and THREE?.OrbitControls?
        return callback()

    _loading_threejs_callbacks.push callback
    #console.log("load_threejs")
    if _loading_threejs_callbacks.length > 1
        #console.log("load_threejs: already loading...")
        return

    run_callbacks = (error) ->
        for callback in _loading_threejs_callbacks
            callback error
        _loading_threejs_callbacks = []

    loadScript math3d.threejs_src, (error) ->
        if (error)
            run_callbacks error
        else
            loadScript math3d.orbitcontrols_src, run_callbacks
    
math3d.load_threejs = load_threejs

_scene_using_renderer  = undefined
_renderer = undefined
dynamic_renderer_type = undefined

get_renderer = (scene) ->
    # if there is a scene currently using this renderer, tell it to switch to
    # the static renderer.
    if _scene_using_renderer? and _scene_using_renderer isnt scene
        _scene_using_renderer.set_static_renderer()

    # now scene takes over using this renderer
    _scene_using_renderer = scene
    if not _renderer?
        # get the best-possible THREE.js renderer (once and for all)
        # based on Detector.js's webgl detection
        try
            if window.WebGLRenderingContext
                canvas = document.createElement 'canvas'
                if canvas.getContext('webgl') or canvas.getContext('experimental-webgl')
                    dynamic_renderer_type = 'webgl'
        if dynamic_renderer_type is 'webgl'
            _renderer = new THREE.WebGLRenderer
                antialias             : true
                alpha                 : true
                preserveDrawingBuffer : true
        else
            dynamic_renderer_type = 'canvas'
            _renderer = new THREE.CanvasRenderer
                antialias : true
                alpha     : true
        _renderer.domElement.className = 'math-3d-dynamic-renderer'

    _renderer

class Math3dThreeJS
    constructor: (parent_element, opts) ->
        @opts = defaults opts,
            width           : undefined
            height          : undefined
            renderer        : undefined  # ignored now
            background      : "#fafafa"
            foreground      : undefined
            spin            : false      # if true, image spins by itself when mouse is over it.
            camera_distance : 10
            aspect_ratio    : undefined  # undefined does nothing or a triple [x,y,z] of length three, which scales the x,y,z coordinates of everything by the given values.
            stop_when_gone  : undefined  # if given, animation, etc., stops when this html element (not jquery!) is no longer in the DOM
            frame           : undefined  # if given call set_frame with opts.frame as input when init_done called
            callback        : undefined  # opts.callback(error, this object)

        load_threejs (error) =>
            if error
                msg = "Error loading THREE.js -- #{error}"
                if @opts.callback?
                    @opts.callback msg
                else
                    console.log msg
            else
                @attach_to_dom parent_element
                @opts.callback? undefined, @

    attach_to_dom: (parent_element) ->
        if @element?
            remove_element @element
        else
            @element = document.createElement 'span'
            @element.className = 'math-3d-viewer'

        parent_element.appendChild @element

    # client code should call this when start adding objects to the scene
    init: ->
        if @_init
            return
        @_init = true

        @init_aspect_ratio_functions()

        @scene = new THREE.Scene()

        # IMPORTANT: There is a major bug in three.js -- if you make the width below more than .5 of the window
        # width, then after 8 3d renders, things get foobared in WebGL mode.  This happens even with the simplest
        # demo using the basic cube example from their site with R68.  It even sometimes happens with this workaround, but
        # at least retrying a few times can fix it.
        if not @opts.width?
            @opts.width  = document.documentElement["clientWidth"]*.5

        @opts.height = if @opts.height? then @opts.height else @opts.width*2/3

        @set_dynamic_renderer()
        @init_orbit_controls()
        @init_on_mouseover()

        # add a bunch of lights
        @init_light()

        # set background color
        @element.style.background = @opts.background

        if not @opts.foreground?
            c = @element.style.background
            if not c? or -1 is c.indexOf ')'
                @opts.foreground = "#000"  # e.g., on firefox - this is best we can do for now
            else
                i = c.indexOf ')'
                z = []
                for a in c.slice(4, i).split ','
                    b = parseInt a
                    if b < 128
                        z.push 255
                    else
                        z.push 0
                @opts.foreground = rgb_to_hex z[0], z[1], z[2]

    # client code should call this when done adding objects to the scene
    init_done: ->
        if @opts.frame?
            @set_frame @opts.frame

        if @renderer_type isnt 'dynamic'
            # if we don't have the renderer, swap it in, make a static image, then give it back to whoever had it.
            owner = _scene_using_renderer
            @set_dynamic_renderer()
            @set_static_renderer()
            owner?.set_dynamic_renderer()

        # possibly show the canvas warning.
        if dynamic_renderer_type is 'canvas'
            @element.title = 'WARNING: using slow non-WebGL canvas renderer'

    set_dynamic_renderer: ->
        # console.log "dynamic renderer"
        if @renderer_type is 'dynamic'
            # already have it
            return

        @renderer = get_renderer @
        @renderer_type = 'dynamic'

        # remove the current renderer (if it exists)
        remove_element @element.lastChild

        # place renderer in correct place in the DOM
        @element.appendChild @renderer.domElement

        @renderer.setClearColor @opts.background, 1
        @renderer.setSize @opts.width, @opts.height
        if @controls?
            @controls.enabled = true
            if @last_canvas_pos?
                @controls.object.position.copy @last_canvas_pos
            if @last_canvas_target?
                @controls.target.copy @last_canvas_target
        if @opts.spin
            @animate render: false
        @render_scene true

    set_static_renderer: ->
        # console.log "static renderer"
        if @renderer_type is 'static'
            # already have it
            return

        if not @static_image?
            @static_image = document.createElement 'img'
            @static_image.className = 'math-3d-static-renderer'
            @static_image.style.width = @opts.width
            @static_image.style.height = @opts.height
        @static_image.src = @data_url()

        @renderer_type = 'static'
        if @controls?
            @controls.enabled = false
            @last_canvas_pos = @controls.object.position
            @last_canvas_target = @controls.target

        # remove the current renderer (if it exists)
        remove_element @element.lastChild

        # place renderer in correct place in the DOM
        @element.appendChild @static_image

    # On mouseover, we switch the renderer out to use webgl, if available, and also enable spin animation.
    init_on_mouseover: ->

        @element.onmouseenter = =>
            @set_dynamic_renderer()

        @element.onmouseleave = =>
            @set_static_renderer()

        @element.onclick = =>
            @set_dynamic_renderer()

    # initialize functions to create new vectors, which take into account the scene's 3d frame aspect ratio.
    init_aspect_ratio_functions: ->
        if @opts.aspect_ratio?
            x = @opts.aspect_ratio[0]
            y = @opts.aspect_ratio[1]
            z = @opts.aspect_ratio[2]
            @vector3 = (a, b, c) -> new THREE.Vector3 x*a, y*b, z*c
            @vector  = (v) -> new THREE.Vector3 x*v[0], y*v[1], z*v[2]
            @aspect_ratio_scale = (v) -> [x*v[0], y*v[1], z*v[2]]
        else
            @vector3 = (a, b, c) -> new THREE.Vector3 a, b, c
            @vector  = (v) -> new THREE.Vector3 v[0], v[1], v[2]
            @aspect_ratio_scale = (v) -> v

    data_url: (opts) ->
        opts = defaults opts,
            type    : 'png'      # 'png' or 'jpeg' or 'webp' (the best)
            quality : undefined   # 1 is best quality; 0 is worst; only applies for jpeg or webp
        # console.log("taking #{JSON.stringify(opts)} snapshot (length=#{s.length})")
        @renderer.domElement.toDataURL "image/#{opts.type}", opts.quality

    init_orbit_controls: ->
        if not @camera?
            @add_camera distance: @opts.camera_distance

        # console.log 'set_orbit_controls'
        # set up camera controls
        @controls = new THREE.OrbitControls @camera, @renderer.domElement
        @controls.damping = 2
        @controls.noKeys = true
        @controls.zoomSpeed = 0.4
        if @_center?
            @controls.target = @_center
        if @opts.spin
            if typeof(@opts.spin) is "boolean"
                @controls.autoRotateSpeed = 2.0
            else
                @controls.autoRotateSpeed = @opts.spin
            @controls.autoRotate = true

        @controls.addEventListener 'change', =>
            if @renderer_type is 'dynamic'
                @rescale_objects()
                @renderer.render @scene, @camera

    add_camera: (opts) ->
        opts = defaults opts,
            distance : 10

        if @camera?
            return

        view_angle = 45
        aspect     = @opts.width/@opts.height
        near       = 0.1
        far        = Math.max 20000, opts.distance*2

        @camera    = new THREE.PerspectiveCamera view_angle, aspect, near, far
        @scene.add @camera
        @camera.position.set opts.distance, opts.distance, opts.distance
        @camera.lookAt @scene.position
        @camera.up = new THREE.Vector3 0, 0, 1

    init_light: (color= 0xffffff) ->

        # console.log 'init_light'

        ambient = new THREE.AmbientLight(0x404040)
        @scene.add ambient

        color = 0xffffff
        d     = 10000000
        intensity = 0.5

        for p in [[d,d,d], [d,d,-d], [d,-d,d], [d,-d,-d],[-d,d,d], [-d,d,-d], [-d,-d,d], [-d,-d,-d]]
            directionalLight = new THREE.DirectionalLight color, intensity
            directionalLight.position.set(p[0], p[1], p[2]).normalize()
            @scene.add directionalLight

        @light = new THREE.PointLight color
        @light.position.set 0, d, 0

    add_text: (opts) ->
        o = defaults opts,
            pos              : [0,0,0]
            text             : required
            fontsize         : 12
            fontface         : 'Arial'
            color            : "#000000"   # anything that is valid to canvas context, e.g., "rgba(249,95,95,0.7)" is also valid.
            constant_size    : true  # if true, then text is automatically resized when the camera moves;
            # WARNING: if constant_size, don't remove text from scene (or if you do, note that it is slightly inefficient still.)

        #console.log("add_text: #{JSON.stringify(o)}")
        # make an HTML5 2d canvas on which to draw text
        width   = 300  # this determines max text width; beyond this, text is cut off.
        height  = 150
        canvas = document.createElement 'canvas'
        canvas.width = width
        canvas.height = height
        context = canvas.getContext "2d"  # get the drawing context

        # set the fontsize and fix for our text.
        context.font = "Normal " + o.fontsize + "px " + o.fontface
        context.textAlign = 'center'

        # set the color of our text
        context.fillStyle = o.color

        # actually draw the text -- right in the middle of the canvas.
        context.fillText o.text, width/2, height/2

        # Make THREE.js texture from our canvas.
        texture = new THREE.Texture canvas
        texture.needsUpdate = true

        # Make a material out of our texture.
        spriteMaterial = new THREE.SpriteMaterial map: texture

        # Make the sprite itself.  (A sprite is a 3d plane that always faces the camera.)
        sprite = new THREE.Sprite spriteMaterial

        # Move the sprite to its position
        p = @aspect_ratio_scale o.pos
        sprite.position.set p[0], p[1], p[2]

        # If the text is supposed to stay constant size, add it to the list of constant size text,
        # which gets resized on scene update.
        if o.constant_size
            if not @_text?
                @_text = [sprite]
            else
                @_text.push sprite

        # Finally add the sprite to our scene
        @scene.add sprite

        return sprite

    add_line : (opts) ->
        o = defaults opts,
            points     : required
            thickness  : 1
            color      : "#000000"
            arrow_head : false  # TODO

        geometry = new THREE.Geometry()
        for a in o.points
            geometry.vertices.push @vector a
        line = new THREE.Line geometry, new THREE.LineBasicMaterial(color:o.color, linewidth:o.thickness)
        @scene.add line

    add_point: (opts) ->
        o = defaults opts,
            loc  : [0,0,0]
            size : 5
            color: "#000000"

        if not @_points?
            @_points = []

        # IMPORTANT: Below we use sprites instead of the more natural/faster PointCloudMaterial.
        # Why?  Because usually people don't plot a huge number of points, and PointCloudMaterial is SQUARE.
        # By using sprites, our points are round, which is something people really care about.

        switch dynamic_renderer_type

            when 'webgl'
                width         = 50
                height        = 50
                canvas        = document.createElement 'canvas'
                canvas.width  = width
                canvas.height = height

                context       = canvas.getContext '2d'  # get the drawing context
                centerX       = width/2
                centerY       = height/2
                radius        = 25

                context.beginPath()
                context.arc centerX, centerY, radius, 0, 2*Math.PI, false
                context.fillStyle = o.color
                context.fill()

                texture = new THREE.Texture canvas
                texture.needsUpdate = true
                spriteMaterial = new THREE.SpriteMaterial map: texture
                particle = new THREE.Sprite spriteMaterial

                p = @aspect_ratio_scale o.loc
                particle.position.set p[0], p[1], p[2]
                @_points.push [particle, o.size/200]

            when 'canvas'
                # inspired by http://mrdoob.github.io/three.js/examples/canvas_particles_random.html
                PI2 = Math.PI * 2
                program = (context) ->
                    context.beginPath()
                    context.arc 0, 0, 0.5, 0, PI2, true
                    context.fill()
                material = new THREE.SpriteCanvasMaterial
                    color   : new THREE.Color o.color
                    program : program
                particle = new THREE.Sprite material
                p = @aspect_ratio_scale o.loc
                particle.position.set p[0], p[1], p[2]
                @_points.push [particle, 4*o.size/@opts.width]
            else
                throw "bug -- unkown dynamic_renderer_type = #{dynamic_renderer_type}"

        @scene.add particle

    add_obj: (myobj) ->
        vertices = myobj.vertex_geometry
        for objects in [0...myobj.face_geometry.length]
            #console.log("object=", JSON.stringify(myobj))
            face3 = myobj.face_geometry[objects].face3
            face4 = myobj.face_geometry[objects].face4
            face5 = myobj.face_geometry[objects].face5

            geometry = new THREE.Geometry()


            for k in [0...vertices.length] by 3
                geometry.vertices.push @vector vertices.slice k, k+3

            # console.log("vertices=",JSON.stringify(geometry.vertices))

            push_face3 = (a, b, c) ->
                geometry.faces.push new THREE.Face3 a-1, b-1, c-1

            # include all faces defined by 3 vertices (triangles)
            for k in [0...face3.length] by 3
                push_face3 face3[k], face3[k+1], face3[k+2]

            # include all faces defined by 4 vertices (squares), which for THREE.js we must define using two triangles
            push_face4 = (a, b, c, d) ->
                push_face3 a, b, c
                push_face3 a, c, d

            for k in [0...face4.length] by 4
                push_face4 face4[k], face4[k+1], face4[k+2], face4[k+3]

            # include all faces defined by 5 vertices (???), which for THREE.js we must define using ten triangles (?)
            for k in [0...face5.length] by 5
                push_face4 face5[k],   face5[k+1], face5[k+2], face5[k+4]
                push_face4 face5[k],   face5[k+1], face5[k+2], face5[k+3]
                push_face4 face5[k],   face5[k+1], face5[k+2], face5[k+4]
                push_face4 face5[k],   face5[k+2], face5[k+3], face5[k+4]
                push_face4 face5[k+1], face5[k+2], face5[k+3], face5[k+4]
           # console.log("faces=",JSON.stringify(geometry.faces))

            geometry.mergeVertices()
            #geometry.computeCentroids()
            geometry.computeFaceNormals()
            #geometry.computeVertexNormals()
            geometry.computeBoundingSphere()

            #finding material key(mk)
            name = myobj.face_geometry[objects].material_name
            mk = 0
            for item in [0..myobj.material.length-1]
                if name is myobj.material[item].name
                    mk = item
                    break

            if @opts.wireframe or myobj.wireframe
                if myobj.color
                    color = myobj.color
                else
                    c = myobj.material[mk].color
                    color = "rgb(#{c[0]*255},#{c[1]*255},#{c[2]*255})"
                if typeof myobj.wireframe is 'number'
                    line_width = myobj.wireframe
                else if typeof @opts.wireframe is 'number'
                    line_width = @opts.wireframe
                else
                    line_width = 1

                material = new THREE.MeshBasicMaterial
                    wireframe          : true
                    color              : color
                    wireframeLinewidth : line_width
                    side               : THREE.DoubleSide
            else if not myobj.material[mk]?
                console.log "BUG -- couldn't get material for ", myobj
                material = new THREE.MeshBasicMaterial
                    wireframe : false
                    color     : "#000000"
            else

                m = myobj.material[mk]

                material =  new THREE.MeshPhongMaterial
                    shininess   : "1"
                    ambient     : 0x0ffff
                    wireframe   : false
                    transparent : m.opacity < 1

                material.color.setRGB    m.color[0],    m.color[1],    m.color[2]
                material.ambient.setRGB  m.ambient[0],  m.ambient[1],  m.ambient[2]
                material.specular.setRGB m.specular[0], m.specular[1], m.specular[2]
                material.opacity = m.opacity

            mesh = new THREE.Mesh geometry, material
            mesh.position.set 0, 0, 0
            @scene.add mesh

    # always call this after adding things to the scene to make sure track
    # controls are sorted out, etc.   Set draw:false, if you don't want to
    # actually *see* a frame.
    set_frame: (opts) ->
        o = defaults opts,
            xmin      : required
            xmax      : required
            ymin      : required
            ymax      : required
            zmin      : required
            zmax      : required
            color     : @opts.foreground
            thickness : .4
            labels    : true  # whether to draw three numerical labels along each of the x, y, and z axes.
            fontsize  : 14
            draw      : true

        @_frame_params = o
        eps = 0.1
        x0 = o.xmin
        x1 = o.xmax
        y0 = o.ymin
        y1 = o.ymax
        z0 = o.zmin
        z1 = o.zmax
        # console.log("set_frame: #{JSON.stringify(o)}")
        if Math.abs(x1 - x0) < eps
            x1 += 1
            x0 -= 1
        if Math.abs(y1 - y0) < eps
            y1 += 1
            y0 -= 1
        if Math.abs(z1 - z0) < eps
            z1 += 1
            z0 -= 1

        mx = (x0+x1)/2
        my = (y0+y1)/2
        mz = (z0+z1)/2
        @_center = @vector3 mx, my, mz

        if @camera?
            d = 1.5*Math.max @aspect_ratio_scale([x1-x0, y1-y0, z1-z0])...
            @camera.position.set mx+d, my+d, mz+d/2
            # console.log("camera at #{JSON.stringify([mx+d,my+d,mz+d])} pointing at #{JSON.stringify(@_center)}")

        if o.draw
            if @frame?
                # remove existing frame
                for x in @frame
                    @scene.remove x
                delete @frame
            @frame = []
            # trace the edges of a cube
            v = [[[x0,y0,z0], [x1,y0,z0], [x1,y1,z0], [x0,y1,z0], [x0,y0,z0],
                  [x0,y0,z1], [x1,y0,z1], [x1,y1,z1], [x0,y1,z1], [x0,y0,z1]],
                 [[x1,y0,z0], [x1,y0,z1]],
                 [[x0,y1,z0], [x0,y1,z1]],
                 [[x1,y1,z0], [x1,y1,z1]]]
            for points in v
                line = @add_line
                    points    : points
                    color     : o.color
                    thickness : o.thickness
                @frame.push line

        if o.draw and o.labels

            if @_frame_labels?
                for x in @_frame_labels
                    @scene.remove x

            @_frame_labels = []

            l = (a, b) ->
                if not b?
                    z = a
                else
                    z = (a+b)/2
                z = z.toFixed 2
                return (z*1).toString()

            txt = (x, y, z, text) =>
                @_frame_labels.push @add_text pos:[x,y,z], text:text, fontsize:o.fontsize, color:o.color, constant_size:false

            offset = 0.075
            if o.draw
                e = (y1 - y0)*offset
                txt x1, y0-e, z0, l z0
                txt x1, y0-e, mz, "z=#{l z0, z1}"
                txt x1, y0-e, z1, l z1

                e = (x1 - x0)*offset
                txt x1+e, y0, z0, l y0
                txt x1+e, my, z0, "y=#{l y0, y1}"
                txt x1+e, y1, z0, l y1

                e = (y1 - y0)*offset
                txt x1, y1+e, z0, l x1
                txt mx, y1+e, z0, "x=#{l x0, x1}"
                txt x0, y1+e, z0, l x0

        v = @vector3 mx, my, mz
        @camera.lookAt v
        if @controls?
            @controls.target = @_center
        @render_scene()

    add_3dgraphics_obj: (opts) ->
        opts = defaults opts,
            obj       : required
            wireframe : undefined
            set_frame : undefined

        for o in opts.obj
            switch o.type
                when 'text'
                    @add_text
                        pos           : o.pos
                        text          : o.text
                        color         : o.color
                        fontsize      : o.fontsize
                        fontface      : o.fontface
                        constant_size : o.constant_size
                when 'index_face_set'
                    if opts.wireframe?
                        o.wireframe = opts.wireframe
                    @add_obj o
                    if o.mesh and not o.wireframe  # draw a wireframe mesh on top of the surface we just drew.
                        o.color='#000000'
                        o.wireframe = o.mesh
                        @add_obj o
                when 'line'
                    delete o.type
                    @add_line o
                when 'point'
                    delete o.type
                    @add_point o
                else
                    console.log "ERROR: no renderer for model number = #{o.id}"
                    return

        if opts.set_frame?
            @set_frame opts.set_frame

        @render_scene true


    animate: (opts = {}) ->
        opts = defaults opts,
            fps       : undefined
            stop      : false
            mouseover : undefined  # ignored now
            render    : true
        #console.log("@animate #{@_animate_started}")
        if @_animate_started and not opts.stop
            return
        @_animate_started = true
        @_animate opts

    _animate: (opts) ->
        #console.log("anim?", @element.length, @opts.element.is(":visible"))

        if @renderer_type is 'static'
            # will try again when we switch to dynamic renderer
            @_animate_started = false
            return

        #if not $(@element).is ":visible"
        if @element.offsetWidth <= 0 and @element.offsetWidth <= 0
            if @opts.stop_when_gone? and not contains document, @opts.stop_when_gone
                # console.log("stop_when_gone removed from document -- quit animation completely")
                @_animate_started = false
            else if not contains document, @element
                # console.log("element removed from document; wait 5 seconds")
                setTimeout (=> @_animate opts), 5000
            else
                # console.log("check again after a second")
                setTimeout (=> @_animate opts), 1000
            return

        if opts.stop
            @_stop_animating = true
            # so next time around will start
            return
        if @_stop_animating
            @_stop_animating = false
            @_animate_started = false
            return
        @render_scene opts.render
        delete opts.render
        f = =>
            requestAnimationFrame (=> @_animate opts)
        if opts.fps? and opts.fps
            setTimeout f, 1000/opts.fps
        else
            f()


    render_scene: (force = false) ->
        if @renderer_type is 'static'
            console.log 'render static -- todo'
            return

        if not @camera?
            return # nothing to do yet

        @controls?.update()

        pos = @camera.position
        if not @_last_pos?
            new_pos = true
            @_last_pos = pos.clone()
        else if @_last_pos.distanceToSquared(pos) > .05
            new_pos = true
            @_last_pos.copy pos
        else
            new_pos = false

        if not new_pos and not force
            return

        # rescale all text in scene
        @rescale_objects()

        @renderer.render @scene, @camera

    _rescale_factor: ->
        if not @_center?
            return undefined
        else
            return @camera.position.distanceTo(@_center) / 3

    rescale_objects: (force = false) ->
        s = @_rescale_factor()
        if not s? or (Math.abs(@_last_scale - s) < 0.000001 and not force)
            return
        @_last_scale = s
        if @_text?
            for sprite in @_text
                sprite.scale.set s, s, s
        if @_frame_labels?
            for sprite in @_frame_labels
                sprite.scale.set s, s, s
        if @_points?
            for z in @_points
                c = z[1]
                z[0].scale.set s*c, s*c, s*c


math3d.render_3d_scene = (opts) ->
    opts = defaults opts,
        scene   : required   # {opts:?, obj:?} or url from which to download (via ajax) a JSON string that parses to {opts:?,obj:?}
        element : required    # DOM element
        cb      : undefined   # cb(err, scene object)
    # Render a 3-d scene
    #console.log("render_3d_scene: url='#{opts.url}'")

    scene_obj = undefined
    async.series([
        (cb) ->
            switch typeof(opts.scene)
                when 'string'
                    $.ajax(
                        url     : opts.scene
                        timeout : 30000
                        success : (data) ->
                            try
                                opts.scene = JSON.parse data
                                cb()
                            catch err
                                cb err
                    ).fail ->
                        cb "error downloading #{opts.scene}"
                when 'object'
                    cb()
                else
                    cb "bad scene value: #{opts.scene}"
        (cb) ->
            # do this initialization *after* we create the 3d renderer
            init = (err, scene) ->
                if err
                    cb err
                else
                    scene_obj = scene
                    scene.init()
                    if opts.scene.obj?
                        scene.add_3dgraphics_obj obj : opts.scene.obj
                    scene.init_done()
                    cb()
            # create the 3d renderer
            opts.scene.opts ?= {}
            opts.scene.opts.callback = init

            obj = new Math3dThreeJS opts.element, opts.scene.opts
    ], (err) ->
        opts.cb? err, scene_obj
    )

if $?
    # jQuery plugin for making a DOM object into a 3d renderer
    $.fn.math3d = (opts = {}) ->
        @each ->
            new Math3dThreeJS @, opts
