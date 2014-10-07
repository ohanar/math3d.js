coffee = require 'coffee-script'
fs = require 'fs'
uglify = require 'uglify-js'

option '-o', '--output=[DIR]', 'directory for compiled code'

SOURCE = 'src'

mkdir_p = (path, callback) ->
    fs.exists path, (exists) ->
        if exists
            fs.stat path, (error, stats) ->
                throw error if error
                if not stats.isDirectory()
                    callback "#{path} is not a directory"
                callback()
        else
            fs.mkdir path, callback

task 'build', 'build math3d.js', (options) ->
    outdir = options.output or 'build'
    compile = (sources) ->
        mkdir_p outdir, (error) ->
            throw error if error
            sources = coffee.compile sources
            fs.writeFile "#{outdir}/math3d.js", sources, (error) ->
                throw error if error
            minified = uglify.minify sources,
                fromString: true
            fs.writeFile "#{outdir}/math3d.min.js", minified.code, (error) ->
                throw error if error
    fs.readdir SOURCE, (error, files) ->
        throw error if error
        concatenate = (sources, index) ->
            if index is files.length
                return compile sources

            file = "#{SOURCE}/#{files[index]}"
            index += 1

            fs.readFile file, 'utf8', (error, contents) ->
                throw error if error
                switch file.split('.').pop()
                    when 'js'
                        concatenate "#{sources}`#{contents}`", index
                    when 'coffee'
                        concatenate sources + contents, index
                    else
                        concatenate sources, index
        concatenate '', 0
