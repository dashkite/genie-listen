import * as Fn from "@dashkite/joy/function"
import * as Time from "@dashkite/joy/time"
import * as W from "@dashkite/masonry-watch"
import Zephyr from "@dashkite/zephyr"
import * as SNS from "@dashkite/dolores/sns"
import * as SQS from "@dashkite/dolores/sqs"
import configuration from "./configuration"

reject = ( f ) ->
  ( rx ) ->
    yield x for await x from rx when !( await f x )

each = ( f ) ->
  ( rx ) ->
    await f x for await x from rx
    return

rebounce = ({ interval, cycle }, f ) -> 
  do ({ state, last } = {}) ->
    state = "ready"
    ->
      last = performance.now()
      switch state
        when "ready"
          state = "waiting"
          do ({ delay, idle } = {}) ->
            delay = interval
            loop
              await Time.sleep delay
              idle = performance.now() - last
              break if idle > interval
              delay = cycle
            state = "running"
            await do f
            while state == "queued"
              state = "running"
              await do f
            state = "ready"
        when "running"
          state = "queued"

      return
  

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
    each rebounce interval: 500, cycle: 100, -> Genie.run "build"
  ]



