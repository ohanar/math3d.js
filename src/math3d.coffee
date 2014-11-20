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

removeElement = (element) ->
    if element? and (parent = element.parentElement)?
        parent.removeChild element

loadScript = (script_src, callback) ->
    runCallback = true

    script = document.createElement 'script'

    script.onload = ->
            removeElement script
            if runCallback
                runCallback = false
                callback()
    script.onerror = ->
            removeElement script
            if runCallback
                runCallback = false
                callback "error loading script #{script.src}"

    script.type = 'text/javascript'
    script.charset = 'utf-8'
    script.async = true
    script.src = script_src

    document.head.appendChild script

_loadingThreejsCallbacks = []
_orbitControlsSetup = false

math3d.threejsSource = "//cdnjs.cloudflare.com/ajax/libs/three.js/r68/three.min.js"
math3d.fontSources = []

math3d.loadThreejs = (callback) ->
    if THREE? and _orbitControlsSetup and not math3d.fontSources.length
        return callback()

    _loadingThreejsCallbacks.push callback
    if _loadingThreejsCallbacks.length > 1
        return

    runCallbacks = (error) ->
        while callback = _loadingThreejsCallbacks.shift()
            callback error

    setupOrbitControls = (callback) ->
        if not _orbitControlsSetup
            OrbitControls.prototype = Object.create THREE.EventDispatcher.prototype
            _orbitControlsSetup = true
        callback()

    setupFonts = (callback) ->
        if math3d.fontSources.length
            loadScript math3d.fontSources.shift(), (error) ->
                if error
                    runCallbacks error
                else
                    setupFonts callback
        else
            callback()

    setupThreejs = (callback) ->
        if THREE?
            callback()
        else
            loadScript math3d.threejsSource, (error) ->
                if error
                    runCallbacks error
                else
                    callback()

    setupThreejs (-> setupFonts (-> setupOrbitControls runCallbacks))

_sceneUsingRenderer = undefined
_renderer = {}
# get the best-possible THREE.js renderer (once and for all)
# based on Detector.js's webgl detection
try
    if @WebGLRenderingContext
        canvas = document.createElement 'canvas'
        if canvas.getContext('webgl') or canvas.getContext('experimental-webgl')
            _defaultRendererType = 'webgl'
if not _defaultRendererType?
    _defaultRendererType = 'canvas'

getRenderer = (scene, type) ->
    # if there is a scene currently using this renderer, tell it to switch to
    # the static renderer.
    if _sceneUsingRenderer? and _sceneUsingRenderer isnt scene
        _sceneUsingRenderer.setStaticRenderer()

    # now scene takes over using this renderer
    _sceneUsingRenderer = scene

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
            background      : [1,1, 1]
            spin            : false     # if true, image spins by itself when mouse is over it.
            aspect_ratio    : [1, 1, 1] # a triple [x,y,z] of length three, which scales the x,y,z coordinates of everything by the given values.
            stop_when_gone  : undefined # if given, animation, etc., stops when this html element (not jquery!) is no longer in the DOM
            frame           : undefined # frame options
            light           : undefined # light options
            callback        : undefined # opts.callback(this object, error)

        @frameOpts = defaults @opts.frame,
            color           : undefined # defaults to the color-wise negation of the background
            thickness       : .4        # zero thickness disables the frame
            labels          : true      # whether or not to enable labels on the axes

        @lightOpts = defaults @opts.light,
            color           : [1, 1, 1]
            intensity       : 0.75

        math3d.loadThreejs (error) =>
            if error
                return @opts.callback? undefined, error

            if @_init
                return @opts.callback? @
            @_init = true

            # IMPORTANT: There is a major bug in three.js -- if you make the width below more than .5 of the window
            # width, then after 8 3d renders, things get foobared in WebGL mode.  This happens even with the simplest
            # demo using the basic cube example from their site with R68.  It even sometimes happens with this workaround, but
            # at least retrying a few times can fix it.
            @opts.width ?= document.documentElement.clientWidth/2
            @opts.height ?= @opts.width*2/3

            # setup aspect ratio stuff
            aspectRatio = @aspectRatio = new THREE.Vector3 @opts.aspect_ratio...
            @scaleSize = @aspectRatio.length()
            @squareScale = (new THREE.Vector3 1, 1, 1).normalize()
            @squareScale.multiplyScalar @scaleSize
            @rescale = (vector) -> vector.multiply aspectRatio

            # initialize the scene
            @scene = new THREE.Scene()

            # functions in render hooks will be run when before rendering
            @renderHooks = []

            @opts.callback? @

    # client code should call this when done adding objects to the scene
    finalize: ->
        @computeDimensions()

        @element = document.createElement 'span'
        @element.className = 'math-3d-viewer'
        @element.style.display = 'inline-block'
        if @opts.renderer is 'canvas'
            # possibly show the canvas warning.
            @element.title = 'WARNING: using slow non-WebGL canvas renderer'

        @setColor()
        @setFrame()
        @setCamera()
        @setOrbitControls()
        @setLight()

        # borrow the renderer to do the initial render
        owner = _sceneUsingRenderer
        wasDynamic = owner? and owner.rendererType is 'dynamic'

        @opts.renderer ?= _defaultRendererType
        @setDynamicRenderer() # used to do the first render

        @setStaticRenderer()

        # then give it back to whoever had it (if they were using it)
        if wasDynamic
            owner.setDynamicRenderer()

        @setOnMouseOver()

        @opts.parent.appendChild @element

    setDynamicRenderer: ->
        if @rendererType is 'dynamic'
            # already have it
            return

        @renderer = getRenderer @, @opts.renderer
        @rendererType = 'dynamic'

        @renderer.setClearColor @background, 1
        @renderer.setSize @opts.width, @opts.height

        @controls.enabled = true

        if @opts.spin
            @animate render: false

        @renderScene true

        # remove the current renderer (if it exists)
        removeElement @element.lastChild

        # place renderer in correct place in the DOM
        @element.appendChild @renderer.domElement

    setStaticRenderer: ->
        if @rendererType is 'static'
            # already have it
            return

        @controls.enabled = false

        if not @staticImage?
            @staticImage = document.createElement 'img'
            @staticImage.className = 'math-3d-static-renderer'
            @staticImage.style.width = @opts.width
            @staticImage.style.height = @opts.height
        @staticImage.src = @dataUrl()

        @rendererType = 'static'

        # remove the current renderer (if it exists)
        removeElement @element.lastChild

        # place renderer in correct place in the DOM
        @element.appendChild @staticImage

    dataUrl: (opts) ->
        opts = defaults opts,
            type    : 'png'      # 'png' or 'jpeg' or 'webp' (the best)
            quality : undefined   # 1 is best quality; 0 is worst; only applies for jpeg or webp
        @renderer.domElement.toDataURL "image/#{opts.type}", opts.quality

    updateBoundingBox: (obj) ->
        obj.geometry.computeBoundingBox()

        if @_boundingBoxHelper?
            @_boundingBoxHelper.copy obj.geometry.boundingBox.clone()
        else
            @_boundingBoxHelper = obj.geometry.boundingBox.clone()

        @_boundingBoxHelper.min.add obj.position
        @_boundingBoxHelper.max.add obj.position

        if @boundingBox?
            @boundingBox.geometry.boundingBox.union @_boundingBoxHelper
        else
            @boundingBox = new THREE.BoxHelper()
            @boundingBox.geometry.boundingBox = @_boundingBoxHelper.clone()
        @boundingBox.update @boundingBox

    _finalizeObj: (obj, in_frame) ->
        obj.scale.copy @aspectRatio

        if in_frame
            @updateBoundingBox obj

        @rescale obj.position

        @scene.add obj
        return obj

    addText: (opts) ->
        opts = defaults opts,
            text        : required
            loc         : [0,0,0]
            fontface    : undefined # defaults to Text3d's default font
            rotation    : undefined # by default will always face the camera
            size        : 1         # should really be specified
            texture     : required

        if not (opts.rotation? or @_text?)
            @_text = []

            up = new THREE.Vector3()
            @renderHooks.push =>
                up.set(0, 1, 0).applyQuaternion @camera.quaternion
                for text in @_text
                    text.up.copy up
                    text.lookAt @camera.position

        opts.depth = 0
        text = @addText3d opts

        if not opts.rotation?
            @_text.push text

        return text

    addText3d: (opts) ->
        opts = defaults opts,
            text        : required
            loc         : [0, 0, 0]
            rotation    : [0, 0, 0]
            fontface    : "helvetiker"
            size        : 1         # should really be specified
            depth       : 1         # ditto
            texture     : required

        geometry = new THREE.TextGeometry opts.text,
            size        : opts.size
            height      : opts.depth
            font        : opts.fontface

        material = new THREE.MeshBasicMaterial
            opacity     : opts.texture.opacity
            transparent : opts.texture.opacity < 1

        material.color.setRGB opts.texture.color...

        text = new THREE.Mesh geometry, material
        text.position.set opts.loc...
        text.rotation.set opts.rotation...

        geometry.computeBoundingBox()

        center = geometry.boundingBox.center()
        tmp = new THREE.Vector3()

        # will be called on render, this is used to make
        # text.rotation be centered on the center of the text
        text.updateMatrix = ->
            @matrix.makeRotationFromQuaternion @quaternion
            @matrix.scale @scale

            tmp.copy(center).applyMatrix4(@matrix).subVectors(@position, tmp)
            @matrix.setPosition tmp

            @matrixWorldNeedsUpdate = true

        @_finalizeObj text, false

        text.scale.copy @squareScale
        return text

    addLine: (opts) ->
        opts = defaults opts,
            points     : required
            thickness  : 1
            arrow_head : false  # TODO
            texture    : required
            in_frame   : true

        geometry = new THREE.Geometry()
        for point in opts.points
            geometry.vertices.push new THREE.Vector3(point...)

        line = new THREE.Line geometry, new THREE.LineBasicMaterial(linewidth:opts.thickness)
        line.material.color.setRGB opts.texture.color...

        return @_finalizeObj line, opts.in_frame

    addSphere: (opts) ->
        opts = defaults opts,
            loc             : [0,0,0]
            radius          : 5
            texture         : required
            in_frame        : true
            _basic_material : false

        geometry = new THREE.SphereGeometry opts.radius, 32, 32

        if opts._basic_material
            material = new THREE.MeshBasicMaterial
                transparent : opts.texture.opacity < 1
        else
            material = new THREE.MeshPhongMaterial
                transparent : opts.texture.opacity < 1
                side        : THREE.DoubleSide

            material.ambient.setRGB     opts.texture.ambient...
            material.specular.setRGB    opts.texture.specular...
        material.color.setRGB       opts.texture.color...
        material.opacity          = opts.texture.opacity

        sphere = new THREE.Mesh geometry, material
        sphere.position.set opts.loc...

        @_finalizeObj sphere, opts.in_frame
        return sphere

    _addCloudPoint: (opts) ->
        if not @_cloud
            @_cloud = {}

        key = opts.size+opts.texture.color+opts.in_frame

        if not (cloud = @_cloud[key])?
            material = new THREE.PointCloudMaterial
                size            : opts.size*2
                sizeAttenuation : false
            material.color.setRGB opts.texture.color...
            cloud = @_cloud[key] = new THREE.PointCloud(
                                        new THREE.Geometry(), material)
            cloud.scale.copy @aspectRatio
            @scene.add cloud

        cloud.geometry.vertices.push new THREE.Vector3(opts.loc...)

        if opts.in_frame
            @updateBoundingBox cloud
        return cloud

    _initPointHelper: ->
        if not @_pointHelper?
            @_pointHelperVec = new THREE.Vector3()

            @_pointHelper = new THREE.Mesh()
            @_pointHelper.geometry.vertices.push @_pointHelperVec

    _addSpherePoint: (opts) ->
        if not @_points?
            @_points = []
            @renderHooks.push =>
                for point in @_points
                    scale = @camera.position.distanceTo point.position
                    point.scale.set scale, scale, scale

        if opts.in_frame
            @_initPointHelper()
            @_pointHelperVec.set opts.loc...
            @updateBoundingBox @_pointHelper

        opts.radius = opts.size/1200
        opts._basic_material = true
        opts.in_frame = false

        delete opts.size
        delete opts.use_cloud

        point = @addSphere opts
        @_points.push point
        return point

    addPoint: (opts) ->
        opts = defaults opts,
            loc         : [0,0,0]
            size        : 5
            texture     : required
            use_cloud   : false     # faster, but you have to use square points
            in_frame    : true

        if opts.use_cloud
            return @_addCloudPoint opts
        else
            return @_addSpherePoint opts

    addIndexFaceSet: (opts) ->
        opts = defaults opts,
            vertices    : required
            faces       : required
            texture     : required
            wireframe   : undefined
            in_frame    : true

        geometry = new THREE.Geometry()

        for vector in opts.vertices
            geometry.vertices.push new THREE.Vector3(vector...)

        for vertex in opts.faces
            a = vertex.shift()
            b = vertex.shift()
            while c = vertex.shift()
                geometry.faces.push new THREE.Face3 a, b, c
                b = c

        geometry.mergeVertices()
        geometry.computeFaceNormals()

        if opts.wireframe
            material = new THREE.MeshBasicMaterial
                wireframe           : true
                wireframeLinewidth  : opts.wireframe
                transparent         : opts.texture.opacity < 1
                side                : THREE.DoubleSide
        else
            material = new THREE.MeshPhongMaterial
                transparent         : opts.texture.opacity < 1
                side                : THREE.DoubleSide
            material.ambient.setRGB     opts.texture.ambient...
            material.specular.setRGB    opts.texture.specular...
        material.color.setRGB       opts.texture.color...
        material.opacity          = opts.texture.opacity

        mesh = new THREE.Mesh geometry, material

        return @_finalizeObj mesh, opts.in_frame

    addGroup: (opts) ->
        opts = defaults opts,
            subobjs     : required

        ret = for obj in opts.subobjs
            @addObj obj
        return ret

    addObj: (opts) ->
        opts = defaults opts, {type: required}, true

        type = opts.type
        delete opts.type

        switch type
            when 'group'
                return @addGroup opts
            when 'text'
                return @addText opts
            when 'text3d'
                return @addText3d opts
            when 'index_face_set'
                return @addIndexFaceSet opts
            when 'line'
                return @addLine opts
            when 'point'
                return @addPoint opts
            when 'sphere'
                return @addSphere opts
            else
                console.log "ERROR: bad object type #{opts.obj.type}"

    computeDimensions: ->
        dim = @rescale @boundingBox.geometry.boundingBox.size()

        @maxDim = Math.max dim.x, dim.y, dim.z
        @minDim = Math.min dim.x, dim.y, dim.z

        @center = @rescale @boundingBox.geometry.boundingBox.center()

    setColor: ->
        # setup color stuff
        @background = new THREE.Color @opts.background...
        @element.style.background = @background.getStyle()
        if @frameOpts.color?
            @frameColor = new THREE.Color @frameOpts.color...
        else
            @frameColor = new THREE.Color(
                1-@background.r, 1-@background.g, 1-@background.b)

    # always call this after adding things to the scene to make sure track
    # controls are sorted out, etc. The client should never have to worry
    # about calling this
    setFrame: ->
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

        if @frameOpts.thickness isnt 0 and not @_bounded
            @_bounded = true

            if not @boundingBox?
                # no objects in the scene
                return

            # set the color and linewidth of the bounding box
            @boundingBox.material.color = @frameColor
            @boundingBox.material.linewidth = @frameOpts.thickness

            # set the scale for the bounding box
            @boundingBox.scale.copy @aspectRatio

            # the update method of BoxHelper disables matrixAutoUpdate but
            # we still need it for the aspect ratio to be taken into account
            @boundingBox.matrixAutoUpdate = true

            # add the bounding box to the scene
            @scene.add @boundingBox

            if @frameOpts.labels and not @_labeled
                @_labeled = true

                min = @boundingBox.geometry.boundingBox.min
                max = @boundingBox.geometry.boundingBox.max
                avg = @boundingBox.geometry.boundingBox.center()

                offset = @maxDim*0.05
                offsets = (new THREE.Vector3 offset, offset, offset).divide @aspectRatio

                textSize = @minDim/@scaleSize/8

                if textSize is 0
                    return

                frameColor = [@frameColor.r, @frameColor.g, @frameColor.b]

                addHashMark = (loc) =>
                    loc2 = new THREE.Vector3 loc...
                    if offsetDir[0] is '+'
                        loc2[offsetDir[1]] += offsets[offsetDir[1]]*0.75
                    else if offsetDir[0] is '-'
                        loc2[offsetDir[1]] -= offsets[offsetDir[1]]*0.75
                    loc2 = [loc2.x, loc2.y, loc2.z]

                    @addLine
                            points     : [loc, loc2]
                            thickness  : @frameOpts.thickness*5
                            in_frame   : false
                            texture    :
                                    color   : frameColor
                                    opacity : 1

                addLabel = (loc, text) =>
                    addHashMark loc

                    text = @addText
                            loc         : loc
                            text        : text
                            size        : textSize
                            texture     :
                                    color   : frameColor
                                    opacity : 1

                    # add a bit of extra offset based on the size of the text
                    textBox = text.geometry.boundingBox.size().multiply @squareScale
                    extraOffset = Math.max(textBox.x, textBox.y, textBox.z)/2

                    realOffset = offset + extraOffset
                    if offsetDir[0] is '+'
                        text.position[offsetDir[1]] += realOffset
                    else if offsetDir[0] is '-'
                        text.position[offsetDir[1]] -= realOffset

                format = (num) ->
                    Number(num.toFixed 2).toString()

                offsetDir = ['-','y']
                addLabel [max.x, min.y, min.z], format(min.z)
                addLabel [max.x, min.y, avg.z], "z = #{format avg.z}"
                addLabel [max.x, min.y, max.z], format(max.z)

                offsetDir = ['+','x']
                addLabel [max.x, min.y, min.z], format(min.y)
                addLabel [max.x, avg.y, min.z], "y = #{format avg.y}"
                addLabel [max.x, max.y, min.z], format(max.y)

                offsetDir = ['+','y']
                addLabel [max.x, max.y, min.z], format(max.x)
                addLabel [avg.x, max.y, min.z], "x = #{format avg.x}"
                addLabel [min.x, max.y, min.z], format(min.x)

    setLight: ->
        ambientLight = new THREE.AmbientLight()
        ambientLight.color.setRGB @lightOpts.color...
        @scene.add ambientLight

        cameraLight = new THREE.PointLight 0, @lightOpts.intensity
        cameraLight.color.setRGB @lightOpts.color...
        @scene.add cameraLight

        @renderHooks.push =>
            cameraLight.position.copy @camera.position

    setCamera: ->
        view_angle = 45
        aspect     = @opts.width/@opts.height
        near = @minDim/4
        far = @maxDim*16

        @camera    = new THREE.PerspectiveCamera view_angle, aspect, near, far
        @camera.up = new THREE.Vector3 0, 0, 1

        @camera.lookAt @center

        @camera.position.set 1.5, 1.5, 0.75
        @camera.position.multiplyScalar(@maxDim).add @center

        @camera.updateProjectionMatrix()

        @scene.add @camera

    setOrbitControls: ->
        # set up camera controls
        @controls = new OrbitControls @camera, @element

        @controls.target = @center

        @controls.damping = 2
        @controls.noKeys = true
        #@controls.zoomSpeed = 0.6

        if @opts.spin
            if typeof @opts.spin is "boolean"
                @controls.autoRotateSpeed = 2.0
            else
                @controls.autoRotateSpeed = @opts.spin
            @controls.autoRotate = true

        @controls.addEventListener 'change', => @renderScene true

    # on mouseover, we switch the renderer out to use the dynamic renderer
    setOnMouseOver: ->

        @element.addEventListener 'mouseover', (=> @setDynamicRenderer()), false

        @element.addEventListener 'mouseleave', (=> @setStaticRenderer()), false

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
        if @rendererType is 'static'
            # will try again when we switch to dynamic renderer
            @_animate_started = false
            return

        if @element.offsetWidth <= 0 and @element.offsetWidth <= 0
            if @opts.stop_when_gone? and not document.contains(@opts.stop_when_gone)
                @_animate_started = false
            else if not document.contains(@element)
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
        @renderScene opts.render
        delete opts.render
        f = =>
            requestAnimationFrame (=> @_animate opts)
        if opts.fps? and opts.fps
            setTimeout f, 1000/opts.fps
        else
            f()

    renderScene: (force = false) ->
        if @_rendering? and @_rendering
            # already in the process of rendering
            return

        if @rendererType isnt 'dynamic'
            # scene's are only rendered when they are dynamic
            return

        if not @camera?
            return # nothing to do yet

        @_rendering = true

        if not force
            position = @camera.position
            if not @_lastPosition?
                force = true
                @_lastPosition = position.clone()
                #@_renderDistance = @minDim*@minDim/10000
            else if @_lastPosition.distanceToSquared(position) > 0.05
                force = true
                @_lastPosition.copy position

        if force
            @controls.update()
            for hook in @renderHooks
                hook()
            @renderer.render @scene, @camera

        @_rendering = false

math3d.render_3d_scene = (opts) ->
    opts = defaults opts,
        scene    : required    # {opts:?, obj:?} or url from which to download (via ajax) a JSON string that parses to {opts:?,obj:?}
        element  : required    # DOM element to attach to
        timeout  : 30000       # milleseconds for timing out fetchs
        callback : undefined   # callback(scene object, error)
    # Render a 3-d scene

    create_scene = (scene) ->
        scene.opts ?= {}

        scene.opts.parent = opts.element

        scene.opts.callback = (sceneobj, error) ->
            if not error
                if scene.obj?
                    sceneobj.addObj scene.obj
                sceneobj.finalize()
            opts.callback? sceneobj, error

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
