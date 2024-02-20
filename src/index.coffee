import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as W from "@dashkite/masonry-watch"
import Zephyr from "@dashkite/zephyr"
import * as SNS from "@dashkite/dolores/sns"
import * as SQS from "@dashkite/dolores/sqs"
import configuration from "./configuration"

reject = ( f ) ->
  ( it ) ->
    yield x for await x from it when !( await f x )

Module =

  isLocal: do ({ local } = {}) ->
    ( events ) ->
      local ?= await Zephyr.read "package.json"
      events.some ({ content }) ->
        content.module == local.name

Listen = do ({ queue, topic } = {}) ->

  configure: 

    Fn.once ->
      topic = await SNS.create configuration.topic
      queue = await SQS.create configuration.queue
      await SNS.subscribe topic, queue
  
  glob: ->    
    loop
      events = await SQS.poll queue
      if events.length > 0
        yield events

export default ( Genie ) ->

  Genie.on "watch", Fn.flow [
    Listen.configure
    Listen.glob
    reject Module.isLocal
    It.each -> 
      console.log "listen: build triggered"
      Genie.run "build"
  ]
