import jester
import std/sequtils
import std/uri
import std/options
import std/json
import std/jsonutils
import std/oids
import std/times
import std/locks

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
proc err[T](code: int, errmsg: string): Result[T] = Result[T](data: none(T), code: code, errmsg: errmsg)


type Fighter = object
  id: string
  name: string
  skill: seq[string]
  createdAt: DateTime

type FighterCreate = object
  name: string
  skill: seq[string]

proc toFighter(a: FighterCreate): Fighter = 
  return Fighter(
    id: $genOid(),
    name: a.name,
    skill: a.skill,
    createdAt: now().utc
  )

settings:
  port = Port(5000)
  bindAddr = "127.0.0.1"


var lock: Lock
initLock(lock)
var fighters = @[
  Fighter(id: $genOid(), name: "隆", skill: @["波动拳"], createdAt: now().utc),
  Fighter(id: $genOid(), name: "肯", skill: @["升龙拳"], createdAt: now().utc)
]

const jsonHeader = {"Content-Type": "application/json; charset=utf-8"}

router fighterApi:
  get "":
    {.cast(gcsafe).}:
      withLock lock:
        resp Http200, jsonHeader, $ok(fighters).toJson

  get "/@name":
    {.cast(gcsafe).}:
      withLock lock:
        let name = decodeUrl(@"name")
        let found = fighters.filterIt( it.name == name )
        resp Http200, jsonHeader, $ok(found).toJson

  get "/@id/details":
    {.cast(gcsafe).}:
      withLock lock:
        let id = @"id"
        let found = fighters.filterIt( it.id == id )
        if found.len > 0:
          resp Http200, jsonHeader, $ok(found[0]).toJson
        else:
          resp Http200, jsonHeader, $ok[Fighter]().toJson

  post "":
    {.cast(gcsafe).}:
      withLock lock:
        let fighterCreate = try:
            parseJson(request.body).jsonTo(FighterCreate)
          except Exception:
            resp Http400, "Bad request body"
            return
        let newFighter = fighterCreate.toFighter
        fighters.add newFighter
        resp Http200, jsonHeader, $ok(newFighter).toJson


  delete "/@id":
    {.cast(gcsafe).}:
      withLock lock:
        let id = @"id"
        let found = fighters.filterIt( it.id == id )
        fighters = fighters.filterIt( it.id != id ) 
        resp Http200, jsonHeader, $ok(found).toJson



routes:
  extend fighterApi, "/fighter"

# TODO: error handle, CORS, DB
