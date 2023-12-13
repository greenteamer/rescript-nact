type persistenceEngine = Nact_bindings.persistenceEngine

type untypedRef = Nact_bindings.actorRef

type actorRef<'msg> = ActorRef(Nact_bindings.actorRef)

module Interop = {
  let fromUntypedRef = reference => ActorRef(reference)
  let toUntypedRef = (ActorRef(reference)) => reference
  let dispatch = Nact_bindings.dispatch
  let dispatchWithSender = Nact_bindings.dispatchWithSender
}

type actorPath = ActorPath(Nact_bindings.actorPath)

module ActorPath = {
  let fromReference = (ActorRef(actor)) => ActorPath(actor.path)
  let systemName = (ActorPath(path)) => path.system
  let toString = (ActorPath(path)) =>
    "system:" ++ (path.system ++ ("//" ++ String.concat("/", Belt.List.fromArray(path.parts))))
  let parts = (ActorPath(path)) => Belt.List.fromArray(path.parts)
}

type systemMsg

%%raw(`
/* This code is to handle how bucklescript sometimes represents variants */

var WrappedVariant = '_wvariant';
var WrappedEvent = '_wevent';
function unsafeEncoder(obj) {
  var data = JSON.stringify(obj, function (key, value) {
    if (value && Array.isArray(value) && value.tag !== undefined) {
      var r = {};
      r.values = value.slice();
      r.tag = value.tag;
      r.type = WrappedVariant;
      return r;
    } else {
      return value;
    }
  });
  return { data: JSON.parse(data), type: WrappedEvent };
};

function unsafeDecoder(result) {
  if(result && typeof(result) === 'object' && result.type === WrappedEvent) {
    var serialized = result.serialized || JSON.stringify(result.data);
    return JSON.parse(serialized, (key, value) => {
      if (value && typeof (value) === 'object' && value.type === WrappedVariant) {
        var values = value.values;
        values.tag = value.tag;
        return values;
      } else {
        return value;
      }
    });
  } else {
    return result;
  }
};
`)

type decoder<'a> = Js.Json.t => 'a

type encoder<'a> = 'a => Js.Json.t

@val external unsafeDecoder: Js.Json.t => 'msg = "unsafeDecoder"

@val external unsafeEncoder: 'msg => Js.Json.t = "unsafeEncoder"

type ctx<'msg, 'parentMsg> = {
  parent: actorRef<'parentMsg>,
  path: actorPath,
  self: actorRef<'msg>,
  children: Belt.Set.String.t,
  name: string,
  /* Sender added for interop purposes. Not to be used for reason only code */
  sender: option<untypedRef>,
}

type persistentCtx<'msg, 'parentMsg> = {
  parent: actorRef<'parentMsg>,
  path: actorPath,
  self: actorRef<'msg>,
  name: string,
  persist: 'msg => Js.Promise.t<unit>,
  children: Belt.Set.String.t,
  recovering: bool,
  /* Sender added for interop purposes. Not to be used for reason only code */
  sender: option<untypedRef>,
}

let mapCtx = (untypedCtx: Nact_bindings.ctx) => {
  name: untypedCtx.name,
  self: ActorRef(untypedCtx.self),
  parent: ActorRef(untypedCtx.parent),
  path: ActorPath(untypedCtx.path),
  children: Belt.Set.String.fromArray(Js.Dict.keys(untypedCtx.children)),
  sender: untypedCtx.sender,
}

let mapPersistentCtx = (untypedCtx: Nact_bindings.persistentCtx<'incoming>) => {
  name: untypedCtx.name,
  self: ActorRef(untypedCtx.self),
  parent: ActorRef(untypedCtx.parent),
  path: ActorPath(untypedCtx.path),
  recovering: untypedCtx.recovering->Belt.Option.getWithDefault(false),
  persist: untypedCtx.persist,
  children: Belt.Set.String.fromArray(Js.Dict.keys(untypedCtx.children)),
  sender: untypedCtx.sender,
}

type supervisionCtx<'msg, 'parentMsg> = {
  parent: actorRef<'parentMsg>,
  path: actorPath,
  self: actorRef<'msg>,
  name: string,
  children: Belt.Set.String.t,
  sender: option<untypedRef>,
}

let mapSupervisionCtx = (untypedCtx: Nact_bindings.supervisionCtx) => {
  name: untypedCtx.name,
  self: ActorRef(untypedCtx.self),
  parent: ActorRef(untypedCtx.parent),
  path: ActorPath(untypedCtx.path),
  children: Belt.Set.String.fromArray(Js.Dict.keys(untypedCtx.children)),
  sender: untypedCtx.sender,
}

type supervisionAction =
  | Stop
  | StopAll
  | Reset
  | ResetAll
  | Escalate
  | Resume

type supervisionPolicy<'msg, 'parentMsg> = (
  'msg,
  exn,
  supervisionCtx<'msg, 'parentMsg>,
) => Js.Promise.t<supervisionAction>

type statefulSupervisionPolicy<'msg, 'parentMsg, 'state> = (
  'msg,
  exn,
  'state,
  supervisionCtx<'msg, 'parentMsg>,
) => ('state, Js.Promise.t<supervisionAction>)

let mapSupervisionFunction = optionalF =>
  switch optionalF {
  | None => None
  | Some(f) =>
    Some(
      (msg, err, ctx) =>
        f(msg, err, mapSupervisionCtx(ctx))->Js.Promise2.then(decision =>
          Js.Promise.resolve(
            switch decision {
            | Stop => ctx.stop
            | StopAll => ctx.stopAll
            | Reset => ctx.reset
            | ResetAll => ctx.resetAll
            | Escalate => ctx.escalate
            | Resume => ctx.resume
            },
          )
        ),
    )
  }

type statefulActor<'state, 'msg, 'parentMsg> = (
  'state,
  'msg,
  ctx<'msg, 'parentMsg>,
) => Js.Promise.t<'state>

type statelessActor<'msg, 'parentMsg> = ('msg, ctx<'msg, 'parentMsg>) => Js.Promise.t<unit>

type persistentActor<'state, 'msg, 'parentMsg> = (
  'state,
  'msg,
  persistentCtx<'msg, 'parentMsg>,
) => Js.Promise.t<'state>

type persistentQuery<'state> = unit => Js.Promise.t<'state>

let useStatefulSupervisionPolicy = (f, initialState) => {
  let state = ref(initialState)
  (msg, err, ctx) => {
    let (nextState, promise) = f(msg, err, state.contents, ctx)
    state := nextState
    promise
  }
}

let spawn = (~name=?, ~shutdownAfter=?, ~onCrash=?, ActorRef(parent), func, initialState) => {
  open Nact_bindings
  let options = {
    initialStateFunc: Some(ctx => initialState(mapCtx(ctx))),
    shutdownAfter,
    onCrash: mapSupervisionFunction(onCrash),
  }
  let f = (state, msg: 'msg, ctx) =>
    try func(state, msg, mapCtx(ctx)) catch {
    | err => Js.Promise.reject(err)
    }
  let untypedRef = Nact_bindings.spawn(parent, f, name, options)
  ActorRef(untypedRef)
}

let spawnStateless = (~name=?, ~shutdownAfter=?, ActorRef(parent), func) => {
  open Nact_bindings
  let options = {
    initialStateFunc: None,
    shutdownAfter,
    onCrash: mapSupervisionFunction(None),
  }
  let f = (msg, ctx) =>
    try func(msg, mapCtx(ctx)) catch {
    | err => Js.Promise.reject(err)
    }
  let untypedRef = Nact_bindings.spawnStateless(parent, f, name, options)
  ActorRef(untypedRef)
}

let spawnPersistent = (
  ~key,
  ~name=?,
  ~shutdownAfter=?,
  ~snapshotEvery=?,
  ~onCrash: option<supervisionPolicy<'msg, 'parentMsg>>=?,
  ~decoder: option<decoder<'msg>>=?,
  ~stateDecoder: option<decoder<'state>>=?,
  ~encoder: option<encoder<'msg>>=?,
  ~stateEncoder: option<encoder<'state>>=?,
  ActorRef(parent),
  func,
  initialState: persistentCtx<'msg, 'parentMsg> => 'state,
) => {
  let decoder = decoder->Belt.Option.getWithDefault(unsafeDecoder)
  let stateDecoder = stateDecoder->Belt.Option.getWithDefault(unsafeDecoder)
  let stateEncoder = stateEncoder->Belt.Option.getWithDefault(unsafeEncoder)
  let encoder = encoder->Belt.Option.getWithDefault(unsafeEncoder)
  let options: Nact_bindings.persistentActorOptions<'msg, 'parentMsg, 'state> = {
    initialStateFunc: ctx => initialState(mapPersistentCtx(ctx)),
    shutdownAfter,
    onCrash: mapSupervisionFunction(onCrash),
    snapshotEvery,
    encoder,
    decoder,
    snapshotEncoder: stateEncoder,
    snapshotDecoder: stateDecoder,
  }
  let f = (state, msg, ctx) =>
    try func(state, msg, mapPersistentCtx(ctx)) catch {
    | err => Js.Promise.reject(err)
    }
  let untypedRef = Nact_bindings.spawnPersistent(parent, f, key, name, options)
  ActorRef(untypedRef)
}

let persistentQuery = (
  ~key,
  ~snapshotKey=?,
  ~cacheDuration=?,
  ~snapshotEvery=?,
  ~decoder=?,
  ~stateDecoder=?,
  ~encoder=?,
  ~stateEncoder=?,
  ActorRef(actor),
  func,
  initialState,
) => {
  let decoder = decoder->Belt.Option.getWithDefault(unsafeDecoder)
  let stateDecoder = stateDecoder->Belt.Option.getWithDefault(unsafeDecoder)
  let stateEncoder = stateEncoder->Belt.Option.getWithDefault(unsafeEncoder)
  let encoder = encoder->Belt.Option.getWithDefault(unsafeEncoder)
  let options: Nact_bindings.persistentQueryOptions<'msg, 'state> = {
    initialState,
    cacheDuration,
    snapshotEvery,
    snapshotKey,
    encoder,
    decoder,
    snapshotEncoder: stateEncoder,
    snapshotDecoder: stateDecoder,
  }
  let f = (state, msg) =>
    try func(state, msg) catch {
    | err => Js.Promise.reject(err)
    }
  Nact_bindings.persistentQuery(actor, f, key, options)
}

let stop = (ActorRef(reference)) => Nact_bindings.stop(reference)

let dispatch = (ActorRef(recipient), msg) => Nact_bindings.dispatch(recipient, msg)

let nobody = () => ActorRef(Nact_bindings.nobody())

let spawnAdapter = (~name=?, parent, mapping) => {
  let f = (msg, _) => parent->dispatch(mapping(msg))->Js.Promise.resolve
  switch name {
  | Some(name) => spawnStateless(~name, parent, f)
  | None => spawnStateless(parent, f)
  }
}

let start = (~name: option<string>=?, ~persistenceEngine=?, ()) => {
  let plugins = switch persistenceEngine {
  | Some(engine) => list{Nact_bindings.configurePersistence(engine)}
  | None => list{}
  }
  let plugins = switch name {
  | Some(name) => list{Obj.magic({"name": name}), ...plugins}
  | None => plugins
  }
  switch plugins {
  | list{a, b, ..._} => ActorRef(Nact_bindings.start([a, b]))
  | list{a} => ActorRef(Nact_bindings.start([a]))
  | list{} => ActorRef(Nact_bindings.start([]))
  }
}

exception QueryTimeout(int)

let query = (~timeout: int, ActorRef(recipient), msgF) => {
  let f = tempReference => msgF(ActorRef(tempReference))
  Js.Promise.catch(
    _ => Js.Promise.reject(QueryTimeout(timeout)),
    Nact_bindings.query(recipient, f, timeout),
  )
}

let milliseconds = 1

let millisecond = milliseconds

let seconds = 1000 * milliseconds

let second = seconds

let minutes = 60 * seconds

let minute = minutes

let hours = 60 * minutes

let messages = 1

let message = 1

// Keep for reason compatibility
module Operators = {
  let \"<-<" = (actorRef, msg) => dispatch(actorRef, msg)
  let \">->" = (msg, actorRef) => dispatch(actorRef, msg)
  let \"<?" = (actor, (f, timeout)) => query(~timeout, actor, f)
}
