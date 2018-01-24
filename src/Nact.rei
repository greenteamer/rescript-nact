module StringSet = Nact_stringSet;

type persistenceEngine;

type systemMsg;

type actorRef('msg);

type actorPath;

module ActorPath: {
  let fromReference: actorRef(_) => actorPath;
  let systemName: actorPath => string;
  let toString: actorPath => string;
};

module Log: {
  /* logEngine is an opaque type which dispatches messages to the logging actor */
  type loggingEngine;
  type name = string;
  type logLevel =
    | Off
    | Trace
    | Debug
    | Info
    | Warn
    | Error
    | Critical;
  type t =
    | Message(logLevel, string, Js.Date.t, actorPath)
    | Error(exn, Js.Date.t, actorPath)
    | Metric(name, Js.Json.t, Js.Date.t, actorPath)
    | Event(name, Js.Json.t, Js.Date.t, actorPath)
    | Unknown(Js.Json.t, Js.Date.t, actorPath);
  type logger = actorRef(systemMsg) => actorRef(t);
  let trace: (string, loggingEngine) => unit;
  let debug: (string, loggingEngine) => unit;
  let info: (string, loggingEngine) => unit;
  let warn: (string, loggingEngine) => unit;
  let error: (string, loggingEngine) => unit;
  let critical: (string, loggingEngine) => unit;
  let event: (~name: string, ~properties: 'eventProperties, loggingEngine) => unit;
  let exception_: (exn, loggingEngine) => unit;
  let metric: (~name: string, ~values: 'values, loggingEngine) => unit;
};

type ctx('msg, 'parentMsg) = {
  parent: actorRef('parentMsg),
  path: actorPath,
  self: actorRef('msg),
  children: StringSet.t,
  name: string,
  logger: Log.loggingEngine
};

type persistentCtx('msg, 'parentMsg) = {
  parent: actorRef('parentMsg),
  path: actorPath,
  self: actorRef('msg),
  name: string,
  persist: 'msg => Js.Promise.t(unit),
  children: StringSet.t,
  recovering: bool,
  logger: Log.loggingEngine
};

type supervisionCtx('msg, 'parentMsg) = {
  parent: actorRef('parentMsg),
  child: string,
  path: actorPath,
  self: actorRef('msg),
  name: string,
  children: StringSet.t
};

type supervisionAction =
  | Stop
  | StopAll
  | Reset
  | ResetAll
  | Escalate
  | Resume;

type statefulActor('state, 'msg, 'parentMsg) =
  ('state, 'msg, ctx('msg, 'parentMsg)) => Js.Promise.t('state);

type statelessActor('msg, 'parentMsg) = ('msg, ctx('msg, 'parentMsg)) => Js.Promise.t(unit);

type persistentActor('state, 'msg, 'parentMsg) =
  ('state, 'msg, persistentCtx('msg, 'parentMsg)) => Js.Promise.t('state);

type supervisionPolicy('msg, 'parentMsg) =
  (exn, supervisionCtx('msg, 'parentMsg)) => Js.Promise.t(supervisionAction);

type statefulSupervisionPolicy('msg, 'parentMsg, 'state) =
  (exn, 'state, supervisionCtx('msg, 'parentMsg)) => ('state, Js.Promise.t(supervisionAction));

let useStatefulSupervisionPolicy:
  (statefulSupervisionPolicy('msg, 'parentMsg, 'state), 'state) =>
  supervisionPolicy('msg, 'parentMsg);

let spawn:
  (
    ~name: string=?,
    ~shutdownAfter: int=?,
    ~whenChildCrashes: supervisionPolicy('msg, 'parentMsg)=?,
    ~decoder: Js.Json.t => 'msg=?,
    actorRef('parentMsg),
    statefulActor('state, 'msg, 'parentMsg),
    'state
  ) =>
  actorRef('msg);

let spawnStateless:
  (
    ~name: string=?,
    ~shutdownAfter: int=?,
    ~whenChildCrashes: supervisionPolicy('msg, 'parentMsg)=?,
    ~decoder: Js.Json.t => 'msg=?,
    actorRef('parentMsg),
    statelessActor('msg, 'parentMsg)
  ) =>
  actorRef('msg);

let spawnPersistent:
  (
    ~key: string,
    ~name: string=?,
    ~shutdownAfter: int=?,
    ~snapshotEvery: int=?,
    ~whenChildCrashes: supervisionPolicy('msg, 'parentMsg)=?,
    ~decoder: Js.Json.t => 'msg=?,
    ~stateDecoder: Js.Json.t => 'state=?,
    ~stateEncoder: 'state => Js.Json.t=?,
    actorRef('parentMsg),
    persistentActor('state, 'msg, 'parentMsg),
    'state
  ) =>
  actorRef('msg);

let spawnAdapter: (actorRef('parentMsg), 'msg => 'parentMsg) => actorRef('msg);

let start:
  (~persistenceEngine: persistenceEngine=?, ~logger: Log.logger=?, unit) => actorRef(systemMsg);

let stop: actorRef('msg) => unit;

let dispatch: (actorRef('msg), 'msg) => unit;

let nobody: unit => actorRef('a);

exception QueryTimeout(int);

let query: (~timeout: int, actorRef('msg), actorRef('outgoing) => 'msg) => Js.Promise.t('outgoing);

let milliseconds: int;

let millisecond: int;

let seconds: int;

let second: int;

let minutes: int;

let minute: int;

let hours: int;

let messages: int;

let message: int;

module Operators: {
  let (<-<): (actorRef('a), 'a) => unit;
  let (>->): ('a, actorRef('a)) => unit;
  let (<?): (actorRef('msg), (actorRef('outgoing) => 'msg, int)) => Js.Promise.t('outgoing);
};