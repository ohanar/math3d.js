###############################################################################
# Copyright (c) 2013, 2014, William Stein and R. Andrew Ohana
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
    document = @document

math3d = (@math3d ?= {})

trunc = (str, max_length) ->
    if not str?.length?
        return str
    if not max_length?
        max_length = 1024
    if str.length > max_length then str.slice(0, max_length-3) + "..." else str

# Returns a new object with properties determined by those of opts and
# base.  The properties in opts *must* all also appear in base.  If an
# base property has value "defaults.required", then it must appear in
# opts.  For each property prop of base not specified in opts, the
# corresponding value opts[prop] is set (all in a new copy of opts) to
# be base[prop].
defaults = (opts, base) ->
    if not opts?
        opts = {}
    args = ->
        try
            "(opts=#{trunc JSON.stringify opts}, base=#{trunc JSON.stringify base})"
        catch
            ""
    if typeof opts isnt 'object'
        # We put explicit traces before the errors in this function,
        # since otherwise they can be very hard to debug.
        console.trace()
        throw "defaults -- TypeError: function takes inputs as an object #{args()}"
    res = {}
    for prop, val of base
        if opts.hasOwnProperty(prop) and opts[prop]?
            res[prop] = opts[prop]
        else if val?  # only record not undefined properties
            if val is defaults.required
                console.trace()
                throw "defaults -- TypeError: property '#{prop}' must be specified #{args()}"
            else
                res[prop] = val
    for prop, val of opts
        if not base.hasOwnProperty(prop)
            console.trace()
            throw "defaults -- TypeError: got an unexpected argument '#{prop}' #{args()}"
    res

# WARNING -- don't accidentally use this as a default:
required = defaults.required = "__!!!!!!this is a required property!!!!!!__"

component_to_hex = (component) ->
    (if component < 16 then "0" else "") + component.toString 16

rgb_to_hex = (r, g, b) -> "#" + component_to_hex(r) + component_to_hex(g) + component_to_hex(b)

remove_element = (element) ->
    if element? and (parent = element.parentElement)?
        parent.removeChild element

loadScript = (script_src, callback) ->
    run_callback = true

    script = document.createElement 'script'

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

    script.type = 'text/javascript'
    script.async = true
    script.src = script_src

    document.head.appendChild script

_loading_threejs_callbacks = []
_orbitcontrols_setup = false

math3d.threejs_src = "//cdnjs.cloudflare.com/ajax/libs/three.js/r68/three.min.js"

math3d.load_threejs = (callback) ->
    if THREE? and _orbitcontrols_setup
        return callback()

    _loading_threejs_callbacks.push callback
    if _loading_threejs_callbacks.length > 1
        return

    run_callbacks = (error) ->
        while callback = _loading_threejs_callbacks.shift()
            callback error

    setup_orbitcontrols = ->
        _orbitcontrols_setup = true
        OrbitControls.prototype = Object.create THREE.EventDispatcher.prototype
        run_callbacks()

    if THREE?
        return setup_orbitcontrols()

    loadScript math3d.threejs_src, (error) ->
        if (error)
            run_callbacks error
        else
            setup_orbitcontrols()

_scene_using_renderer = undefined
_renderer = {}
# get the best-possible THREE.js renderer (once and for all)
# based on Detector.js's webgl detection
try
    if @WebGLRenderingContext
        canvas = document.createElement 'canvas'
        if canvas.getContext('webgl') or canvas.getContext('experimental-webgl')
            _default_renderer_type = 'webgl'
if not _default_renderer_type?
    _default_renderer_type = 'canvas'

get_renderer = (scene, type) ->
    # if there is a scene currently using this renderer, tell it to switch to
    # the static renderer.
    if _scene_using_renderer? and _scene_using_renderer isnt scene
        _scene_using_renderer.set_static_renderer()

    # now scene takes over using this renderer
    _scene_using_renderer = scene

    if not _renderer[type]?
        switch type
            when 'webgl'
                _renderer[type] = new THREE.WebGLRenderer
                    antialias             : true
                    alpha                 : true
                    preserveDrawingBuffer : true
            when 'canvas'
                _renderer[type] = new THREE.CanvasRenderer
                    antialias : true
                    alpha     : true
            else
                throw "bug -- unkown dynamic renderer type = #{type}"
        _renderer[type].domElement.className = 'math-3d-dynamic-renderer'

    _renderer[type]

class Math3dThreeJS
    constructor: (opts) ->
        @opts = defaults opts,
            parent          : required
            width           : undefined
            height          : undefined
            renderer        : undefined  # 'webgl' or 'canvas' or undefined to choose best
            background      : "#ffffff"
            foreground      : undefined
            spin            : false      # if true, image spins by itself when mouse is over it.
            camera_distance : 10
            aspect_ratio    : undefined  # undefined does nothing or a triple [x,y,z] of length three, which scales the x,y,z coordinates of everything by the given values.
            stop_when_gone  : undefined  # if given, animation, etc., stops when this html element (not jquery!) is no longer in the DOM
            frame           : undefined  # if given call set_frame with opts.frame as input when init_done called
            callback        : undefined  # opts.callback(error, this object)

        math3d.load_threejs (error) =>
            if error
                return @opts.callback? error

            @attach_to_dom @opts.parent

            if @_init
                return @opts.callback? undefined, @
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
                    @opts.foreground = rgb_to_hex z...

            @opts.callback? undefined, @

    attach_to_dom: (parent_element) ->
        if @element?
            remove_element @element
        else
            @element = document.createElement 'span'
            @element.className = 'math-3d-viewer'

        parent_element.appendChild @element

    # client code should call this when done adding objects to the scene
    finalize: ->
        if @opts.frame?
            @set_frame @opts.frame

        if @renderer_type isnt 'dynamic'
            # if we don't have the renderer, swap it in, make a static image, then give it back to whoever had it.
            owner = _scene_using_renderer
            @set_dynamic_renderer()
            @set_static_renderer()
            owner?.set_dynamic_renderer()

        # possibly show the canvas warning.
        if @opts.renderer is 'canvas'
            @element.title = 'WARNING: using slow non-WebGL canvas renderer'

    set_dynamic_renderer: ->
        if @renderer_type is 'dynamic'
            # already have it
            return

        @opts.renderer ?= _default_renderer_type
        @renderer = get_renderer @, @opts.renderer
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
            [x, y, z] = @opts.aspect_ratio
            @vector = (a, b, c) -> new THREE.Vector3 x*a, y*b, z*c
            @aspect_ratio_scale = (a, b, c) -> [x*a, y*b, z*c]
        else
            @vector = (a, b, c) -> new THREE.Vector3 a, b, c
            @aspect_ratio_scale = (a, b, c) -> [a, b, c]

    data_url: (opts) ->
        opts = defaults opts,
            type    : 'png'      # 'png' or 'jpeg' or 'webp' (the best)
            quality : undefined   # 1 is best quality; 0 is worst; only applies for jpeg or webp
        @renderer.domElement.toDataURL "image/#{opts.type}", opts.quality

    init_orbit_controls: ->
        if not @camera?
            @add_camera distance: @opts.camera_distance

        # set up camera controls
        @controls = new OrbitControls @camera, @renderer.domElement
        @controls.damping = 2
        @controls.noKeys = true
        @controls.zoomSpeed = 0.4
        if @_center?
            @controls.target = @_center
        if @opts.spin
            if typeof @opts.spin is "boolean"
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
        ambient = new THREE.AmbientLight(0x404040)
        @scene.add ambient

        color = 0xffffff
        d     = 10000000
        intensity = 0.5

        for p in [[d,d,d], [d,d,-d], [d,-d,d], [d,-d,-d],[-d,d,d], [-d,d,-d], [-d,-d,d], [-d,-d,-d]]
            directionalLight = new THREE.DirectionalLight color, intensity
            directionalLight.position.set(p...).normalize()
            @scene.add directionalLight

        @light = new THREE.PointLight color
        @light.position.set 0, d, 0

    add_text: (opts) ->
        opts = defaults opts,
            pos              : [0,0,0]
            text             : required
            fontsize         : 12
            fontface         : 'Arial'
            color            : "#000000"   # anything that is valid to canvas context, e.g., "rgba(249,95,95,0.7)" is also valid.
            constant_size    : true  # if true, then text is automatically resized when the camera moves;
            # WARNING: if constant_size, don't remove text from scene (or if you do, note that it is slightly inefficient still.)

        # make an HTML5 2d canvas on which to draw text
        width   = 300  # this determines max text width; beyond this, text is cut off.
        height  = 150
        canvas = document.createElement 'canvas'
        canvas.width = width
        canvas.height = height
        context = canvas.getContext "2d"  # get the drawing context

        # set the fontsize and fix for our text.
        context.font = "Normal " + opts.fontsize + "px " + opts.fontface
        context.textAlign = 'center'

        # set the color of our text
        context.fillStyle = opts.color

        # actually draw the text -- right in the middle of the canvas.
        context.fillText opts.text, width/2, height/2

        # Make THREE.js texture from our canvas.
        texture = new THREE.Texture canvas
        texture.needsUpdate = true

        # Make a material out of our texture.
        spriteMaterial = new THREE.SpriteMaterial map: texture

        # Make the sprite itself.  (A sprite is a 3d plane that always faces the camera.)
        sprite = new THREE.Sprite spriteMaterial

        # Move the sprite to its position
        position = @aspect_ratio_scale opts.pos...
        sprite.position.set position...

        # If the text is supposed to stay constant size, add it to the list of constant size text,
        # which gets resized on scene update.
        if opts.constant_size
            if not @_text?
                @_text = [sprite]
            else
                @_text.push sprite

        # Finally add the sprite to our scene
        @scene.add sprite

        return sprite

    add_line : (opts) ->
        opts = defaults opts,
            points     : required
            thickness  : 1
            color      : "#000000"
            arrow_head : false  # TODO

        geometry = new THREE.Geometry()
        for a in opts.points
            geometry.vertices.push @vector a...
        line = new THREE.Line geometry, new THREE.LineBasicMaterial(color:opts.color, linewidth:opts.thickness)
        @scene.add line

    add_point: (opts) ->
        opts = defaults opts,
            loc  : [0,0,0]
            size : 5
            color: "#000000"

        if not @_points?
            @_points = []

        # IMPORTANT: Below we use sprites instead of the more natural/faster PointCloudMaterial.
        # Why?  Because usually people don't plot a huge number of points, and PointCloudMaterial is SQUARE.
        # By using sprites, our points are round, which is something people really care about.

        switch @opts.renderer

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
                context.fillStyle = opts.color
                context.fill()

                texture = new THREE.Texture canvas
                texture.needsUpdate = true
                spriteMaterial = new THREE.SpriteMaterial map: texture
                particle = new THREE.Sprite spriteMaterial

                position = @aspect_ratio_scale opts.loc...
                particle.position.set position...
                @_points.push [particle, opts.size/200]

            when 'canvas'
                # inspired by http://mrdoob.github.io/three.js/examples/canvas_particles_random.html
                PI2 = Math.PI * 2
                program = (context) ->
                    context.beginPath()
                    context.arc 0, 0, 0.5, 0, PI2, true
                    context.fill()
                material = new THREE.SpriteCanvasMaterial
                    color   : new THREE.Color opts.color
                    program : program
                particle = new THREE.Sprite material
                position = @aspect_ratio_scale opts.loc...
                particle.position.set position...
                @_points.push [particle, 4*opts.size/@opts.width]

            else
                throw "bug -- unkown dynamic renderer type = #{@opts.renderer}"

        @scene.add particle

    add_index_face_set: (obj) ->
        geometry = new THREE.Geometry()

        for vertex in obj.vertex_geometry
            geometry.vertices.push @vector vertices...

        for points in obj.face_geometry.faces
            a = points.shift()
            b = points.shift()
            while c = points.shift()
                geometry.faces.push new THREE.Face3 a-1, b-1, c-1
                b = c

        geometry.mergeVertices()
        #geometry.computeCentroids()
        geometry.computeFaceNormals()
        #geometry.computeVertexNormals()
        geometry.computeBoundingSphere()

        if @opts.wireframe or obj.wireframe
            if typeof obj.wireframe is 'number'
                line_width = obj.wireframe
            else if typeof @opts.wireframe is 'number'
                line_width = @opts.wireframe
            else
                line_width = 1

            material = new THREE.MeshBasicMaterial
                wireframe          : true
                wireframeLinewidth : line_width
                side               : THREE.DoubleSide

            material.color.setRGB obj.color...
        else if not obj.material?
            console.log "BUG -- couldn't get material for ", obj
            material = new THREE.MeshBasicMaterial
                wireframe : false
                color     : "#000000"
        else
            material =  new THREE.MeshPhongMaterial
                shininess   : "1"
                ambient     : 0x0ffff
                wireframe   : false
                transparent : obj.material.opacity < 1

            material.color.setRGB    obj.material.color...
            material.ambient.setRGB  obj.material.ambient...
            material.specular.setRGB obj.material.specular...
            material.opacity = obj.material.opacity

        mesh = new THREE.Mesh geometry, material
        mesh.position.set 0, 0, 0
        @scene.add mesh

    # always call this after adding things to the scene to make sure track
    # controls are sorted out, etc.   Set draw:false, if you don't want to
    # actually *see* a frame.
    set_frame: (opts) ->
        opts = defaults opts,
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

        eps = 0.1
        x0 = opts.xmin
        x1 = opts.xmax
        y0 = opts.ymin
        y1 = opts.ymax
        z0 = opts.zmin
        z1 = opts.zmax
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
        @_center = @vector mx, my, mz

        if @camera?
            d = 1.5*Math.max @aspect_ratio_scale(x1-x0, y1-y0, z1-z0)...
            @camera.position.set mx+d, my+d, mz+d/2

        if opts.draw
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
                    color     : opts.color
                    thickness : opts.thickness
                @frame.push line

        if opts.draw and opts.labels

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
                @_frame_labels.push(
                    @add_text
                        pos           : [x,y,z]
                        text          : text
                        fontsize      : opts.fontsize
                        color         : opts.color
                        constant_size : false
                    )

            offset = 0.075
            if opts.draw
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

        v = @vector mx, my, mz
        @camera.lookAt v
        if @controls?
            @controls.target = @_center
        @render_scene()

    add_3dgraphics_obj: (opts) ->
        opts = defaults opts,
            obj       : required
            wireframe : undefined
            set_frame : undefined

        for obj in opts.obj
            switch obj.type
                when 'text'
                    delete obj.type
                    @add_text obj
                when 'index_face_set'
                    delete obj.type
                    if opts.wireframe?
                        obj.wireframe = opts.wireframe
                    @add_index_face_set obj
                    if obj.mesh and not obj.wireframe  # draw a wireframe mesh on top of the surface we just drew.
                        obj.material.color = [0, 0, 0]
                        obj.wireframe = obj.mesh
                        @add_index_face_set obj
                when 'line'
                    delete obj.type
                    @add_line obj
                when 'point'
                    delete obj.type
                    @add_point obj
                else
                    console.log "ERROR: bad object type #{obj.type}"

        if opts.set_frame?
            @set_frame opts.set_frame

        @render_scene true

    animate: (opts = {}) ->
        opts = defaults opts,
            fps       : undefined
            stop      : false
            mouseover : undefined  # ignored now
            render    : true
        if @_animate_started and not opts.stop
            return
        @_animate_started = true
        @_animate opts

    _animate: (opts) ->
        if @renderer_type is 'static'
            # will try again when we switch to dynamic renderer
            @_animate_started = false
            return

        #if not $(@element).is ":visible"
        if @element.offsetWidth <= 0 and @element.offsetWidth <= 0
            if @opts.stop_when_gone? and not contains document, @opts.stop_when_gone
                @_animate_started = false
            else if not contains document, @element
                setTimeout (=> @_animate opts), 5000
            else
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
        scene    : required    # {opts:?, obj:?} or url from which to download (via ajax) a JSON string that parses to {opts:?,obj:?}
        element  : required    # DOM element to attach to
        timeout  : 30000       # milleseconds for timing out fetchs
        callback : undefined   # callback(error, scene object)
    # Render a 3-d scene

    create_scene = (scene) ->
        scene.opts ?= {}

        scene.opts.parent = opts.element

        scene.opts.callback = (error, sceneobj) ->
            if not error
                if scene.obj?
                    sceneobj.add_3dgraphics_obj obj : scene.obj
                sceneobj.finalize()
            opts.callback? error, sceneobj

        new Math3dThreeJS scene.opts

    switch typeof opts.scene
        when 'object'
            create_scene opts.scene
        when 'string'
            xhr = new XMLHttpRequest()
            xhr.timeout = opts.timeout
            xhr.onload = ->
                if @status is 200 # success
                    try
                        create_scene JSON.parse @responseText
                    catch error
                        opts.callback? error
                else
                    opts.callback? "errno #{@status} when trying to download #{opts.scene}"
            xhr.onerror = ->
                opts.callback? "error when trying to download #{opts.scene}"
            xhr.onabort = ->
                opts.callback? "downloading #{opts.scene} aborted"
            xhr.ontimeout = ->
                opts.callback? "downloading #{opts.scene} timed out"

            xhr.open 'get', opts.scene
            xhr.send()
        else
            opts.callback? "bad scene type #{typeof opts.scene}"
