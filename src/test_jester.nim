import jester
import mapster
import jsony
import debby/sqlite
import std/[uri, options, times, os]


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

# ------ logging -----------------------

# addHandler(newConsoleLogger())

# ------ std json ----------------------

# json serialize/deserialize DateTime
# proc toJsonHook(dt: DateTime, opt = initToJsonOptions()): JsonNode = % $dt
# proc fromJsonHook(dt: var DateTime, jsonNode: JsonNode) =
#   dt = jsonNode.getStr().parse("yyyy-MM-dd'T'HH:mm:sszzz", utc())

# ------ jsony -------------------------

proc dumpHook*(s: var string, v: DateTime) =
  s.add '"'
  s.add $v
  s.add '"'
proc parseHook*(s: string, i: var int, v: var DateTime) =
  var str: string
  parseHook(s, i, str)
  v = parse(str, "yyyy-MM-dd'T'HH:mm:sszzz", utc())



# ------ orm --------------------------

type Fighter = ref object
  id: int
  name: string
  skill: seq[string]
  createdAt: DateTime
  updatedAt: Option[DateTime] = none DateTime


var fighters = @[
  Fighter(name: "隆", skill: @["波动拳"], createdAt: now().utc),
  Fighter(name: "肯", skill: @["升龙拳"], createdAt: now().utc)
]

let db = openDatabase("fighter.db")
db.dropTableIfExists(Fighter)
db.createTable(Fighter)
db.createIndexIfNotExists(Fighter, "name")
db.withTransaction:
  db.insert(fighters)



# ------ model -------------------------

type FighterCreate = object
  name: string
  skill: seq[string]

type FighterEdit = object
  name: string
  skill: seq[string]

proc toFighter(a: FighterCreate): Fighter {.map.} =
  result.createdAt = now().utc

proc mergeFighter(a: var Fighter, b: FighterEdit) {.inplaceMap.} =
  a.updatedAt = now().utc.some



# ------ server ------------------------

const port = 5000
let startupInfo = initStartupInfo(port)
echo "Startup info: ", startupInfo

settings:
  port = Port(port)
  bindAddr = "127.0.0.1"
  reusePort = true

const jsonHeader = {"Content-Type": "application/json; charset=utf-8"}

router fighterRouter:
  get "":
    {.cast(gcsafe).}:
      let all = db.filter(Fighter, 1 == 1)
      resp Http200, jsonHeader, ok(all).toJson

  get "/@name":
    {.cast(gcsafe).}:
      let name = decodeUrl(@"name")
      let found = db.filter(Fighter, it.name == name)
      resp Http200, jsonHeader, ok(found).toJson

  post "":
    {.cast(gcsafe).}:
      let fighterCreate = try:
          request.body.fromJson(FighterCreate)
        except Exception:
          resp Http400, "Bad request body"
          return
      let newFighter = fighterCreate.toFighter
      db.withTransaction:
        db.insert(newFighter)
      resp Http200, jsonHeader, ok(newFighter).toJson

  put "":
    {.cast(gcsafe).}:
      let fighterEdit = try:
          request.body.fromJson(FighterEdit)
        except Exception:
          resp Http400, "Bad request body"
          return
      var found: seq[Fighter]
      db.withTransaction:
        found = db.filter(Fighter, it.name == fighterEdit.name)
        for v in found.mitems():
          mergeFighter(v, fighterEdit)
          db.update(v)
      resp Http200, jsonHeader, ok(found).toJson

  delete "/@name":
    {.cast(gcsafe).}:
      let name = decodeUrl(@"name")
      var found: seq[Fighter]
      db.withTransaction:
        found = db.filter(Fighter, it.name == name)
        db.delete(found)
      resp Http200, jsonHeader, ok(found).toJson


routes:
  extend fighterRouter, "/fighter"

# TODO: error handle, CORS
