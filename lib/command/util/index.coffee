path  = require 'path'
fs    = require 'fs'

color = require('ansi-color').set
_     = require 'lodash'
wrench = require 'wrench'

logger = require '../../util/logger'
fileUtils = require '../../util/file'

defaults = require './defaults'

baseDirRegex = /([^[\/\\\\]*]*)$/

gatherProjectPossibilities = (callback) ->
  compilerPath = path.join __dirname, '..', '..', 'compilers'
  files = fileUtils.glob "#{compilerPath}/**/*-compiler.coffee"
  logger.debug "Compilers:\n#{files.join('\n')}"
  compilers = {css:[], javascript:[], template:[]}

  for file in files
    comp = require(file)
    comp.fileName = path.basename(file, ".coffee").replace("-compiler","")
    key = baseDirRegex.exec(path.dirname(file))[0]
    compilers[key].push comp

  for comp in compilers.css
    # just need to check SASS
    if comp.checkIfExists?
      comp.checkIfExists (exists) =>
        unless exists
          logger.debug "Compiler for file [[ #{comp.fileName} ]], is not installed/available"
          comp.prettyName = comp.prettyName + color(" (This is not installed and would need to be before use)", "yellow+bold")
        callback(compilers)
      break

fetchConfiguredCompilers = (config, persist = false) ->
  compilers = [new (require("../../compilers/copy"))(config)]
  for category, catConfig of config.compilers
    try
      continue if catConfig.compileWith is "none"
      compiler = require "../../compilers/#{category}/#{catConfig.compileWith}-compiler"
      compilers.push(new compiler(config))
      logger.info "Adding compiler: #{category}/#{catConfig.compileWith}-compiler" if persist
    catch err
      logger.info "Unable to find matching compiler for #{category}/#{catConfig.compileWith}: #{err}"
  compilers

processConfig = (opts, callback) ->
  configPath = _findConfigPath()
  {config} = require configPath if configPath?
  unless config?
    logger.warn "No configuration file found (mimosa-config.coffee), running from current directory using Mimosa's defaults."
    logger.warn "Run 'mimosa config' to copy the default Mimosa configuration to the current directory."
    config = {}
    configPath = path.dirname path.resolve('right-here.foo')

  logger.debug "Your mimosa config:\n#{JSON.stringify(config, null, 2)}"

  config.virgin =       opts?.virgin
  config.isServer =     opts?.server
  config.optimize =     opts?.optimize
  config.min =          opts?.minify
  config.isForceClean = opts?.force

  defaults.applyAndValidateDefaults config, configPath, (err, newConfig) =>
    if err
      logger.fatal "Unable to start Mimosa, #{err} configuration(s) problems listed above."
      process.exit 1
    else
      callback(newConfig)

_findConfigPath = (configPath = path.resolve('mimosa-config.coffee')) ->
  if fs.existsSync configPath
    logger.debug "Found mimosa-config: [[ #{configPath} ]]"
    configPath
  else
    logger.debug "Unable to find mimosa-config at #{configPath}"
    configPath = path.join(path.dirname(configPath), '..', 'mimosa-config.coffee')
    logger.debug "Trying #{configPath}"
    if configPath.length is 'mimosa-config.coffee'.length + 1
      logger.debug "Unable to find mimosa-config"
      return null
    _findConfigPath(configPath)

cleanCompiledDirectories = (config) ->
  items = wrench.readdirSyncRecursive(config.watch.sourceDir)
  files = items.filter (f) -> fs.statSync(path.join(config.watch.sourceDir, f)).isFile()
  directories = items.filter (f) -> fs.statSync(path.join(config.watch.sourceDir, f)).isDirectory()
  directories = _.sortBy(directories, 'length').reverse()

  compilers = fetchConfiguredCompilers(config)

  _cleanMisc(config, compilers)
  _cleanFiles(config, files, compilers)
  _cleanDirectories(config, directories)

  logger.success "[[ #{config.watch.compiledDir} ]] has been cleaned."

_cleanMisc = (config, compilers) ->
  jsDir = path.join config.watch.compiledDir, config.compilers.javascript.directory
  files = fileUtils.glob "#{jsDir}/**/*-built.js"
  for file in files
    logger.debug("Deleting '-built' file, [[ #{file} ]]")
    fs.unlinkSync file

  compiledJadeFile = path.join config.watch.compiledDir, 'index.html'
  if fs.existsSync compiledJadeFile
    logger.debug("Deleting compiledJadeFile [[ #{compiledJadeFile} ]]")
    fs.unlinkSync compiledJadeFile

  logger.debug("Calling individual compiler cleanups")
  compiler.cleanup() for compiler in compilers when compiler.cleanup?

_cleanFiles = (config, files, compilers) ->
  for file in files
    compiledPath = path.join config.watch.compiledDir, file

    extension = path.extname(file)
    if extension?.length > 0
      extension = extension.substring(1)
      compiler = _.find compilers, (comp) ->
        for ext in comp.getExtensions()
          return true if extension is ext
        return false
      if compiler? and compiler.getOutExtension()
        compiledPath = compiledPath.replace(/\.\w+$/, ".#{compiler.getOutExtension()}")

    if fs.existsSync compiledPath
      logger.debug "Deleting file [[ #{compiledPath} ]]"
      fs.unlinkSync compiledPath

_cleanDirectories = (config, directories) ->
  for dir in directories
    dirPath = path.join(config.watch.compiledDir, dir)
    if fs.existsSync dirPath
      logger.debug "Deleting directory [[ #{dirPath} ]]"
      fs.rmdir dirPath, (err) ->
        if err?.code is not "ENOTEMPTY"
          logger.error "Unable to delete directory, #{dirPath}"
          logger.error err


module.exports = {
  processConfig: processConfig
  fetchConfiguredCompilers: fetchConfiguredCompilers
  projectPossibilities:gatherProjectPossibilities
  cleanCompiledDirectories:cleanCompiledDirectories

}