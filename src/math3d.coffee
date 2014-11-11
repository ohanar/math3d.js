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
    if str.length > max_length then str[0...max_length-3] + "..." else str

# Returns a new object with properties determined by those of opts and
# base.  The properties in opts *must* all also appear in base.  If an
# base property has value "defaults.required", then it must appear in
# opts.  For each property prop of base not specified in opts, the
# corresponding value opts[prop] is set (all in a new copy of opts) to
# be base[prop].
defaults = (opts, base, allow_extra = false) ->
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

    optsHasProp = (prop) -> opts.hasOwnProperty and opts[prop]?

    res = {}
    for prop, val of base
        if val? and not optsHasProp(prop) # only record not undefined properties
            if val is defaults.required
                console.trace()
                throw "defaults -- TypeError: property '#{prop}' must be specified #{args()}"
            else
                res[prop] = val

    for prop, val of opts
        if not (allow_extra or base.hasOwnProperty(prop))
            console.trace()
            throw "defaults -- TypeError: got an unexpected argument '#{prop}' #{args()}"
        if val? # only record not undefined properties
            res[prop] = val
    return res

# WARNING -- don't accidentally use this as a default:
required = defaults.required = "__!!!!!!this is a required property!!!!!!__"

rescale_to_hex = (val) ->
    val = Math.round 255*val
    (if val < 16 then "0" else "") + val.toString 16

rgb_to_hex = (rgb) -> '#'+rgb.map(rescale_to_hex).join('')

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
            renderer        : undefined # 'webgl' or 'canvas' or undefined to choose best
            background      : [1,1,1]
            spin            : false     # if true, image spins by itself when mouse is over it.
            camera_distance : 10
            aspect_ratio    : undefined # undefined does nothing or a triple [x,y,z] of length three, which scales the x,y,z coordinates of everything by the given values.
            stop_when_gone  : undefined # if given, animation, etc., stops when this html element (not jquery!) is no longer in the DOM
            frame           : undefined # frame options
            callback        : undefined # opts.callback(error, this object)

        @frameOpts = defaults @opts.frame,
            color           : undefined # defaults to the color-wise negation of the background
            thickness       : .4        # zero thickness disables the frame
            labels          : true      # whether or not to enable labels on the axes

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
            @background = new THREE.Color @opts.background...
            @element.style.background = @background.getStyle()

            if @frameOpts.color?
                @frameColor = new THREE.Color @frameOpts.color...
            else
                @frameColor = new THREE.Color(
                    1-@background.r, 1-@background.g, 1-@background.b)

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
        @set_frame()
        @render_scene()

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

        @renderer.setClearColor @background, 1
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
            @opts.aspect_ratio = new THREE.Vector3 @opts.aspect_ratio...
            @vector = (a, b, c) -> (new THREE.Vector3 a, b, c).multiply(@opts.aspect_ratio)
            @aspect_ratio_scale = (a, b, c) -> [x*a, y*b, z*c]
        else
            @opts.aspect_ratio = new THREE.Vector3 1, 1, 1
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
                if @_3dText?
                    up = (new THREE.Vector3 0, 1, 0).applyQuaternion @camera.quaternion
                    for mesh in @_3dText
                        mesh.up = up.clone()
                        mesh.lookAt @camera.position
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

    updateBoundingBox: (obj) ->
        if not obj.geometry.boundingBox?
            obj.geometry.computeBoundingBox()
        if @boundingBox?
            @boundingBox.geometry.boundingBox.union obj.geometry.boundingBox
        else
            @boundingBox = new THREE.BoxHelper()
            @boundingBox.geometry.boundingBox = obj.geometry.boundingBox.clone()
        @boundingBox.update @boundingBox

    add_text: (opts) ->
        opts = defaults opts,
            loc              : [0,0,0]
            text             : required
            fontsize         : 12
            fontface         : 'Arial'
            material         : required
            constant_size    : true  # if true, then text is automatically resized when the camera moves;
            in_frame         : true
            # WARNING: if constant_size, don't remove text from scene (or if you do, note that it is slightly inefficient still.)

        # make an HTML5 2d canvas on which to draw text
        canvas = document.createElement 'canvas'
        canvas.width   = 300  # this determines max text width; beyond this, text is cut off.
        canvas.height  = 150
        context = canvas.getContext '2d'  # get the drawing context

        # set the fontsize and fix for our text.
        context.font = 'Bold ' + opts.fontsize + 'px ' + opts.fontface
        context.textAlign = 'center'

        # set the color of our text
        context.fillStyle = rgb_to_hex opts.material.color

        # actually draw the text -- right in the middle of the canvas.
        context.fillText opts.text, canvas.width/2, canvas.height/2

        # Make THREE.js texture from our canvas.
        texture = new THREE.Texture canvas
        texture.needsUpdate = true

        # Make a material out of our texture.
        spriteMaterial = new THREE.SpriteMaterial
            map     : texture
            opacity : opts.material.opacity

        # Make the sprite itself.  (A sprite is a 3d plane that always faces the camera.)
        sprite = new THREE.Sprite spriteMaterial

        # Move the sprite to its position
        position = @aspect_ratio_scale opts.loc...
        sprite.position.set position...

        # If the text is supposed to stay constant size, add it to the list of constant size text,
        # which gets resized on scene update.
        if opts.constant_size
            if not @_text?
                @_text = [sprite]
            else
                @_text.push sprite

        # Finally add the sprite to our scene
        if opts.in_frame
            @updateBoundingBox sprite
        @scene.add sprite
        return sprite

    add_3dtext: (opts) ->
        opts = defaults opts,
            text        : required
            loc         : [0, 0, 0]
            rotation    : undefined # by default will always face the camera
            size        : 1
            depth       : 1
            material    : required
            in_frame    : true

        geometry = new THREE.TextGeometry opts.text,
            size        : opts.size
            height      : opts.depth
            font        : "helvetiker"

        material =  new THREE.MeshBasicMaterial
            opacity     : opts.material.opacity
            transparent : opts.material.opacity < 1

        material.color.setRGB    opts.material.color...

        mesh = new THREE.Mesh geometry, material
        mesh.position.set opts.loc...

        geometry.computeBoundingBox()

        center = geometry.boundingBox.center()

        # will be called on render, this is used to make
        # mesh.rotation be centered on the center of the text
        mesh.updateMatrix = ->
            @matrix.makeRotationFromQuaternion @quaternion

            tmp = center.clone().applyMatrix4 @matrix
            tmp.subVectors @position, tmp

            @matrix.setPosition tmp

            @matrixWorldNeedsUpdate = true

        if opts.rotation?
            mesh.rotation.set opts.rotation...
        else if @_3dText?
            @_3dText.push mesh
        else
            @_3dText = [mesh]

        if opts.in_frame
            @updateBoundingBox mesh
        @scene.add mesh
        return mesh

    add_line: (opts) ->
        opts = defaults opts,
            points     : required
            thickness  : 1
            arrow_head : false  # TODO
            material   : required
            in_frame   : true

        geometry = new THREE.Geometry()
        for point in opts.points
            geometry.vertices.push @vector(point...)

        line = new THREE.Line geometry, new THREE.LineBasicMaterial(linewidth:opts.thickness)
        line.material.color.setRGB opts.material.color

        if opts.in_frame
            @updateBoundingBox line
        @scene.add line
        return line

    add_point: (opts) ->
        opts = defaults opts,
            loc  : [0,0,0]
            size : 5
            material: required
            in_frame: true

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
                context.fillStyle = rgb_to_hex opts.material.color
                context.fill()

                texture = new THREE.Texture canvas
                texture.needsUpdate = true
                spriteMaterial = new THREE.SpriteMaterial
                    map     : texture
                    opacity : opts.material.opacity
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
                    color   : new THREE.Color opts.material.color
                    program : program
                particle = new THREE.Sprite material
                position = @aspect_ratio_scale opts.loc...
                particle.position.set position...
                @_points.push [particle, 4*opts.size/@opts.width]

            else
                throw "bug -- unkown dynamic renderer type = #{@opts.renderer}"

        if opts.in_frame
            @updateBoundingBox particle
        @scene.add particle
        return particle

    add_index_face_set: (opts) ->
        opts = defaults opts,
            vertices    : required
            faces       : required
            material    : required
            wireframe   : undefined
            in_frame    : true

        geometry = new THREE.Geometry()

        for vector in opts.vertices
            geometry.vertices.push @vector(vector...)

        for vertex in opts.faces
            a = vertex.shift()
            b = vertex.shift()
            while c = vertex.shift()
                geometry.faces.push new THREE.Face3 a, b, c
                b = c

        geometry.mergeVertices()
        #geometry.computeCentroids()
        geometry.computeFaceNormals()
        #geometry.computeVertexNormals()
        geometry.computeBoundingSphere()

        if @opts.wireframe or opts.wireframe
            if typeof opts.wireframe is 'number'
                line_width = opts.wireframe
            else if typeof @opts.wireframe is 'number'
                line_width = @opts.wireframe
            else
                line_width = 1

            material = new THREE.MeshBasicMaterial
                wireframe          : true
                wireframeLinewidth : line_width
                side               : THREE.DoubleSide

            material.color.setRGB opts.color...
        else
            material =  new THREE.MeshPhongMaterial
                wireframe   : false
                transparent : opts.material.opacity < 1
                side        : THREE.DoubleSide

            material.color.setRGB    opts.material.color...
            material.ambient.setRGB  opts.material.ambient...
            material.specular.setRGB opts.material.specular...
            material.opacity = opts.material.opacity

        mesh = new THREE.Mesh geometry, material
        mesh.position.set 0, 0, 0

        if opts.in_frame
            @updateBoundingBox mesh
        @scene.add mesh
        return mesh

    add_group: (opts) ->
        opts = defaults opts,
            subobjs     : required

        return opts.subobjs.map @add_obj

    add_obj: (opts) ->
        opts = defaults opts, {type: required}, true

        switch opts.type
            when 'group'
                delete opts.type
                return @add_group opts
            when 'text'
                delete opts.type
                return @add_text opts
            when 'index_face_set'
                delete opts.type
                return @add_index_face_set opts
            when 'line'
                delete opts.type
                return @add_line opts
            when 'point'
                delete opts.type
                return @add_point opts
            else
                console.log "ERROR: bad object type #{opts.obj.type}"

    # always call this after adding things to the scene to make sure track
    # controls are sorted out, etc.   Set draw:false, if you don't want to
    # actually *see* a frame.
    set_frame: ->
        ###
        if Math.abs(x1 - x0) < eps
            x1 += 1
            x0 -= 1
        if Math.abs(y1 - y0) < eps
            y1 += 1
            y0 -= 1
        if Math.abs(z1 - z0) < eps
            z1 += 1
            z0 -= 1
        ###

        min = @boundingBox.geometry.boundingBox.min
        max = @boundingBox.geometry.boundingBox.max
        avg = @boundingBox.geometry.boundingBox.center()
        dim = @boundingBox.geometry.boundingBox.size()

        @_center = avg

        if @camera?
            d = 1.5*Math.max(dim.x, dim.y, dim.z)
            @camera.position.set avg.x+d, avg.y+d, avg.z+d/2

        @camera.lookAt @_center
        if @controls?
            @controls.target = @_center

        if @frameOpts.thickness isnt 0 and not @_bounded
            @_bounded = true

            # set the color and linewidth of the bounding box
            @boundingBox.material.color = @frameColor
            @boundingBox.material.linewidth = @frameOpts.thickness

            # add the bounding box to the scene
            @scene.add @boundingBox

            if @frameOpts.labels and not @_labeled
                @_labeled = true

                maxDim = Math.max(dim.x, dim.y, dim.z)
                textSize = Math.min(dim.x, dim.y, dim.z)/10
                textDepth = textSize/100

                if textSize is 0
                    return

                frameColor = [@frameColor.r, @frameColor.g, @frameColor.b]
                offset = maxDim*0.05

                addLabel = (loc, text) =>
                    loc2 = new THREE.Vector3 loc...
                    if offsetDirection[0] is '+'
                        loc2[offsetDirection[1]] += offset*0.75
                    else if offsetDirection[0] is '-'
                        loc2[offsetDirection[1]] -= offset*0.75
                    loc2 = [loc2.x, loc2.y, loc2.z]

                    @add_line
                            points     : [loc, loc2]
                            thickness  : @frameOpts.thickness*4
                            in_frame   : false
                            material   :
                                    color   : frameColor
                                    opacity : 1

                    text = @add_3dtext
                            loc         : loc
                            text        : text
                            size        : textSize
                            depth       : textDepth
                            in_frame    : false
                            material    :
                                    color   : frameColor
                                    opacity : 1

                    textBox = text.geometry.boundingBox.size()
                    extraOffset = Math.max(textBox.x, textBox.y, textBox.z)*0.5
                    realOffset = offset + extraOffset
                    if offsetDirection[0] is '+'
                        text.position[offsetDirection[1]] += realOffset
                    else if offsetDirection[0] is '-'
                        text.position[offsetDirection[1]] -= realOffset

                format = (vec, coord) =>
                    num = vec[coord]/@opts.aspect_ratio[coord]
                    Number(num.toFixed 2).toString()

                offsetDirection = ['-','y']
                addLabel [max.x, min.y, min.z], format(min, 'z')
                addLabel [max.x, min.y, avg.z], "z = #{format avg, 'z'}"
                addLabel [max.x, min.y, max.z], format(max, 'z')

                offsetDirection = ['+','x']
                addLabel [max.x, min.y, min.z], format(min, 'y')
                addLabel [max.x, avg.y, min.z], "y = #{format avg, 'y'}"
                addLabel [max.x, max.y, min.z], format(max, 'y')

                offsetDirection = ['+','y']
                addLabel [max.x, max.y, min.z], format(max, 'x')
                addLabel [avg.x, max.y, min.z], "x = #{format avg, 'x'}"
                addLabel [min.x, max.y, min.z], format(min, 'x')

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
        if @renderer_type isnt 'dynamic'
            # if we don't have the renderer, swap it in, make a static image,
            # then give it back to whoever had it.
            owner = _scene_using_renderer
            @set_dynamic_renderer()
            @set_static_renderer()
            owner?.set_dynamic_renderer()
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
                    sceneobj.add_obj scene.obj
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
