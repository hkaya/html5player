require './test_case'
Download = require '../src/download'
sinon    = require 'sinon'
{Ajax}   = require 'ajax'
{expect} = require 'chai'


describe 'Download', ->

  beforeEach ->
    @now     = 142460040000
    @sandbox = sinon.sandbox.create
      useFakeServer: false
    @sandbox.useFakeTimers(@now)

    @http     = @injector.getInstance Ajax
    @download = @injector.getInstance Download
    @cache    = @download._cache

  afterEach ->
    @sandbox.restore()

  it 'should have a cacheSizeInBytes', ->
    expect(@download.cacheSizeInBytes()).to.equal 0

  it 'should calculate cacheSizeInBytes of the cache', ->
    download = @injector.getInstance Download
    @cache['http://honk.example'] =
      cachedAt:     (new Date).getTime()
      dataUrl:      'blob://somethingsomething'
      sizeInBytes:  5000
      mimeType:     'image/png'
    expect(download.cacheSizeInBytes()).to.equal 5000

  it 'should calculate accurate cacheSizeInBytes', (done) ->
    assetUrl = 'http://detroit.gov/dice_game2.gif'
    @http.match url: assetUrl, type: 'GET', (req, promise) ->
      promise.resolve
        size: 34523
        type: 'image/jpeg'

    @download.request(url: assetUrl).then =>
      expect(@download.cacheSizeInBytes()).to.equal 34523
      done()

  it 'should clear the cache every 6 hours'

  it 'should have @shouldCache as true if not Cortex.net.download', ->
    expect(@download.shouldCache()).to.be.true

  it 'should have @shouldCache as false if Cortex.net.download', ->
    download = @injector.getInstance Download
    download.net = download: ->
    expect(download.shouldCache()).to.be.false

  context 'when asset is not cached', ->

    beforeEach ->
      URL.createObjectURL.returns('blob:someblob')

    it 'should make the request with responseType == "blob"', (done) ->
      assetUrl = 'http://detroit.gov/dice_game.gif'
      @http.match url: assetUrl, type: 'GET', (req, promise) ->
        expect(req.responseType).to.equal 'blob'
        done()

      @download.request(url: assetUrl)

    it 'should add to the cache with cachedAt timestamp', (done) ->
      assetUrl = 'http://detroit.gov/dice_game.gif'
      @http.match url: assetUrl, type: 'GET', (req, promise) ->
        promise.resolve response: sinon.stub()

      @download.request(url: assetUrl).then (response) =>
        expect(@cache[assetUrl].cachedAt).to.equal @now
        done()

    it 'should put dataUrl from URL.createObjectURL in cache', (done) ->
      assetUrl = 'http://detroit.gov/dice_game.gif'
      @http.match url: assetUrl, type: 'GET', (req, promise) ->
        promise.resolve response: sinon.stub()

      @download.request(url: assetUrl).then (response) =>
        expect(@cache[assetUrl].dataUrl).to.equal 'blob:someblob'
        done()

    it 'should add to the cache the size (in bytes) of the asset', (done) ->
      assetUrl = 'http://detroit.gov/dice_game.gif'
      @http.match url: assetUrl, type: 'GET', (req, promise) ->
        promise.resolve size: 1234

      @download.request(url: assetUrl).then =>
        expect(@cache[assetUrl].sizeInBytes).to.equal 1234
        done()

    it 'should add to the cache the mimeType', (done) ->
      assetUrl = 'http://detroit.gov/dice_game.gif'
      @http.match url: assetUrl, type: 'GET', (req, promise) ->
        promise.resolve
          size: 34523
          type: 'image/jpeg'

      @download.request(url: assetUrl).then =>
        expect(@cache[assetUrl].mimeType).to.equal 'image/jpeg'
        done()

    it 'should resolve with the data uri', (done) ->
      assetUrl = 'http://detroit.gov/dice_game.gif'
      @http.match url: assetUrl, type: 'GET', (req, promise) ->
        promise.resolve
          size: 34523
          type: 'image/jpeg'

      @download.request(url: assetUrl).then (path) ->
        expect(path).to.equal 'blob:someblob'
        done()

  context 'when asset is already cached', ->

    beforeEach ->
      @assetUrl = 'http://detroit.gov/dice_game.gif'
      @cache[@assetUrl] =
        cachedAt:     141000000400
        lastSeenAt:   141000000400
        dataUrl:      'blob:somethingsomething'
        sizeInBytes:  5000
        mimeType:     'image/png'
      @download = @injector.getInstance Download

    it 'should update the lastSeenAt time of the cached asset', (done) ->
      @http.match url: @assetUrl, type: 'GET', (req, promise) ->
        promise.resolve
          size: 34523
          type: 'image/jpeg'

      @download.request(url: @assetUrl).then =>
        expect(@cache[@assetUrl].lastSeenAt).to.equal @now
        done()

    it 'should resolve with the data url', (done) ->
      @http.match url: @assetUrl, type: 'GET', (req, promise) ->
        promise.resolve
          size: 34523
          type: 'image/jpeg'

      @download.request(url: @assetUrl).then (path) ->
        expect(path).to.equal 'blob:somethingsomething'
        done()

  context 'when expire runs', ->

    beforeEach ->
      # set lastSeenAt to 7 hours ago to ensure it is the one that expires
      # since the default expiry for assets is 6 hours
      @cache['http://asset.example.com/1.jpg'] =
        cachedAt:     (new Date).getTime() - (9 * 60 * 60 * 1000)
        lastSeenAt:   (new Date).getTime() - (7 * 60 * 60 * 1000)
        dataUrl:      'blob://somethingsomething1'
        sizeInBytes:  5000
        mimeType:     'image/png'
      @cache['http://asset.example.com/2.webm'] =
        cachedAt:     (new Date).getTime()
        lastSeenAt:     (new Date).getTime() - 1000
        dataUrl:      'blob://somethingsomething2'
        sizeInBytes:  5000
        mimeType:     'video/webm'

      @download = @injector.getInstance Download

    it 'should remove expired assets from the store every 15 minutes', ->
      @sandbox.clock.tick(15 * 60 * 1000)

      expect(@cache['http://asset.example.com/1.jpg']).to.not.exist
      expect(@cache['http://asset.example.com/2.webm']).to.exist

    context 'and assets should expire', ->

      it 'should call URL.revokeObjectURL with the dataUrl', ->
        @sandbox.clock.tick(15 * 60 * 1000)
        expect(URL.revokeObjectURL).to.have.been.calledOnce
        expect(URL.revokeObjectURL).to.have.been
          .calledWith 'blob://somethingsomething1'

  context 'when Cortex API is available', ->

    beforeEach ->
      @cortexDownload = @injector.getInstance Download

    it 'should call Cortex.net.download', ->
      fakeCortexNet =
        download: sinon.spy()
      @sandbox.stub @cortexDownload, 'net', fakeCortexNet
      @cortexDownload.request url: 'http://example.com/honk.jpg'
      expect(fakeCortexNet.download).to.have.been.calledWith(
        'http://example.com/honk.jpg',
        cache:
          ttl: 21600000
          mode: 'normal'
      )

    context 'on success', ->

      it 'should resolve with the local file path', ->
        fakeCortexNet =
          download: (uri, opts, success, error) ->
            success('file:///tmp/.somepath')
        @sandbox.stub @cortexDownload, 'net', fakeCortexNet
        confirm = sinon.spy()
        req = @cortexDownload.request url: 'http://example.com/honk.jpg'
        req
          .then confirm
          .done()

        expect(confirm).to.have.been.calledOnce
        expect(confirm).to.have.been.calledWith 'file:///tmp/.somepath'

    context 'on error', ->

      it 'should reject with the error', ->
        err = new Error('WRONG')
        fakeCortexNet =
          download: (uri, opts, success, error) ->
            error(err)
        @sandbox.stub @cortexDownload, 'net', fakeCortexNet
        confirm = sinon.spy()
        req = @cortexDownload.request url: 'http://example.com/honk.jpg'
        req
          .catch confirm
          .done()

        expect(confirm).to.have.been.calledOnce
        expect(confirm).to.have.been.calledWith err
