import jester
import mapster
import stdx/sequtils
import std/sequtils
import std/uri
import std/options
import std/json
import std/jsonutils
import std/oids
import std/times
import std/os
# import std/locks

# json serialize/deserialize DateTime
proc toJsonHook(dt: DateTime, opt = initToJsonOptions()): JsonNode = % $dt
proc fromJsonHook(dt: var DateTime, jsonNode: JsonNode) =
  dt = jsonNode.getStr().parse("yyyy-MM-dd'T'HH:mm:sszzz", utc())


type Result[T] = object
  data: Option[T]
  code: int
  errmsg: string

proc ok[T](): Result[T] = Result[T](data: none(T), code: 200, errmsg: "")
proc ok[T](data: T): Result[T] = Result[T](data: some(data), code: 0, errmsg: "")
proc ok[T](data: Option[T]): Result[T] = Result[T](data: data, code: 0, errmsg: "")
proc err[T](code: int, errmsg: string): Result[T] = Result[T](data: none(T),
    code: code, errmsg: errmsg)


type StartupInfo = object
  release_mode: bool
  multi_threads: bool
  pid: int
  port: int

proc initStartupInfo(port: int): StartupInfo =
  when defined(release):
    const release_mode = true
  else:
    const release_mode = false

  when compileOption("threads"):
    const multi_threads = true
  else:
    const multi_threads = false

  result = StartupInfo(
    release_mode: release_mode,
    multi_threads: multi_threads,
    pid: os.getCurrentProcessId(),
    port: port
  )

const port = 5000
let startupInfo = initStartupInfo(port)

echo "Startup info: ", startupInfo

settings:
  port = Port(port)
  bindAddr = "127.0.0.1"
  reusePort = true



type Fighter = ref object
  id: string
  name: string
  skill: seq[string]
  createdAt: DateTime
  updatedAt: Option[DateTime] = none(DateTime)

type FighterCreate = object
  name: string
  skill: seq[string]

type FighterEdit = object
  name: string
  skill: seq[string]

proc toFighter(a: FighterCreate): Fighter {.map.} = 
  result.id = $genOid()
  result.createdAt = now().utc

proc mergeFighter(a: var Fighter, b: FighterEdit) {.inplaceMap.} = 
  a.updatedAt = now().utc.some


# var lock: Lock
# initLock(lock)

var fighters = @[
  Fighter(id: $genOid(), name: "隆", skill: @["波动拳"], createdAt: now().utc),
  Fighter(id: $genOid(), name: "肯", skill: @["升龙拳"], createdAt: now().utc)
]

const jsonHeader = {"Content-Type": "application/json; charset=utf-8"}

router fighterRouter:
  get "":
    {.cast(gcsafe).}:
      # withLock lock:
        resp Http200, jsonHeader, $ok(fighters).toJson

  get "/@name":
    {.cast(gcsafe).}:
      # withLock lock:
        let name = decodeUrl(@"name")
        let found = fighters.findIt(it.name == name)
        resp Http200, jsonHeader, $ok(found).toJson

  post "":
    {.cast(gcsafe).}:
      # withLock lock:
        let fighterCreate = try:
            parseJson(request.body).jsonTo(FighterCreate)
          except Exception:
            resp Http400, "Bad request body"
            return
        let newFighter = fighterCreate.toFighter
        fighters.add newFighter
        resp Http200, jsonHeader, $ok(newFighter).toJson

  put "":
    {.cast(gcsafe).}:
      # withLock lock:
        let fighterEdit = try:
            parseJson(request.body).jsonTo(FighterEdit)
          except Exception:
            resp Http400, "Bad request body"
            return
        var found = fighters.findIt(it.name == fighterEdit.name)
        if found != nil:
          mergeFighter(found, fighterEdit)
          resp Http200, jsonHeader, $ok(found).toJson
        else:
          resp Http200, jsonHeader, $ok[Fighter]().toJson

  delete "/@name":
    {.cast(gcsafe).}:
      # withLock lock:
        let name = decodeUrl(@"name")
        let found = fighters.findIt(it.name == name)
        fighters = fighters.filterIt(it.name != name)
        resp Http200, jsonHeader, $ok(found).toJson


routes:
  extend fighterRouter, "/fighter"

# TODO: error handle, CORS, DB
