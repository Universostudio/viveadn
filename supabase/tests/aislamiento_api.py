"""Aislamiento entre iglesias a traves de la API (PostgREST), con dos usuarios de prueba.

Repite como peticiones HTTP los ataques de adn_aislamiento_total.sql: cada usuario intenta leer, modificar, borrar e
insertar filas de la otra iglesia en todas las tablas con iglesia_id, llama a las funciones que no debe poder llamar,
y un visitante sin sesion intenta leerlo todo. Al final compara una instantanea de la base (filas y huella por
iglesia y tabla) tomada antes y despues: nada puede haber cambiado.

Uso (lo lanza tests/aislamiento_api.sh, que siembra y limpia los datos):
    python3 tests/aislamiento_api.py <api_url> <uuid_usuario_A> <iglesia_A> <uuid_usuario_B> <iglesia_B>
con PGDATABASE (y el resto de variables de libpq) apuntando a la base de pruebas.
"""
import base64, hashlib, hmac, json, os, subprocess, sys, urllib.error, urllib.request

SECRETO = b"secreto-de-prueba-local-de-32-caracteres-min"  # el de tests/postgrest.conf
API, USER_A, IG_A, USER_B, IG_B = sys.argv[1:6]
fallos = []
comprobaciones = 0


def b64(d: bytes) -> str:
    return base64.urlsafe_b64encode(d).rstrip(b"=").decode()


def jwt(sub: str) -> str:
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64(json.dumps({"role": "authenticated", "sub": sub, "exp": 4102444800}).encode())
    return f"{h}.{p}.{b64(hmac.new(SECRETO, f'{h}.{p}'.encode(), hashlib.sha256).digest())}"


def http(metodo, ruta, token=None, cuerpo=None, devolver=True):
    cab = {"Content-Type": "application/json"}
    if token:
        cab["Authorization"] = "Bearer " + token
    if devolver:
        cab["Prefer"] = "return=representation"
    req = urllib.request.Request(API + ruta, method=metodo, headers=cab, data=None if cuerpo is None else json.dumps(cuerpo).encode())
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try:
            return e.code, json.loads(txt)
        except ValueError:
            return e.code, txt


def psql(sql: str) -> str:
    return subprocess.run(["psql", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True, check=True).stdout


def comprobar(ok: bool, msg: str):
    global comprobaciones
    comprobaciones += 1
    if not ok:
        fallos.append(msg)
        print("FALLO:", msg)


def sin_filas(estado, cuerpo):
    # Bloqueado: error de permisos (401/403) o respuesta correcta sin ninguna fila
    return estado in (401, 403) or (200 <= estado < 300 and not cuerpo)


# Tablas con iglesia_id, descubiertas en la propia API (el OpenAPI de PostgREST)
_, esquema = http("GET", "/")
tablas = sorted(t for t, d in esquema["definitions"].items() if "iglesia_id" in d.get("properties", {}))
comprobar(len(tablas) >= 20, f"la API expone al menos 20 tablas con iglesia_id (expone {len(tablas)})")


def instantanea():
    union = " union all ".join(
        f"select '{t}', iglesia_id::text, count(*), coalesce(md5(string_agg(to_jsonb(x)::text, ',' order by to_jsonb(x)::text)), '') "
        f"from public.{t} x group by iglesia_id" for t in tablas)
    return sorted(psql(union).splitlines())


antes = instantanea()
muestras = {}
for t in tablas:
    for ig in (IG_A, IG_B):
        fila = psql(f"select to_jsonb(x) from public.{t} x where iglesia_id = '{ig}' limit 1").strip()
        if fila:
            muestras[(t, ig)] = json.loads(fila)

for nombre, user, propia, otra in (("A", USER_A, IG_A, IG_B), ("B", USER_B, IG_B, IG_A)):
    tok = jwt(user)
    propias = 0
    for t in tablas:
        e, c = http("GET", f"/{t}?select=iglesia_id&iglesia_id=neq.{propia}", tok)
        comprobar(sin_filas(e, c), f"{nombre} no lee filas ajenas de {t} (estado {e}, {str(c)[:80]})")
        e, c = http("GET", f"/{t}?select=iglesia_id&iglesia_id=eq.{otra}", tok)
        comprobar(sin_filas(e, c), f"{nombre} no lee filas de la otra iglesia en {t} con filtro (estado {e})")
        e, c = http("GET", f"/{t}?select=iglesia_id&iglesia_id=eq.{propia}&limit=1", tok)
        propias += 1 if (e == 200 and c) else 0
        e, c = http("PATCH", f"/{t}?iglesia_id=eq.{otra}", tok, {"iglesia_id": otra})
        comprobar(sin_filas(e, c), f"{nombre} no modifica filas ajenas de {t} (estado {e}, {str(c)[:80]})")
        e, c = http("DELETE", f"/{t}?iglesia_id=eq.{otra}", tok)
        comprobar(sin_filas(e, c), f"{nombre} no borra filas ajenas de {t} (estado {e}, {str(c)[:80]})")
        fila = muestras.get((t, otra))
        if fila:
            if isinstance(fila.get("id"), str) and len(fila["id"]) == 36:
                fila["id"] = "ee000000-0000-0000-0000-00000000dead"
            else:
                fila.pop("id", None)
            e, c = http("POST", f"/{t}", tok, fila, devolver=False)
            comprobar(e >= 400, f"{nombre} no inserta en {t} una fila a nombre de la otra iglesia (estado {e})")
    comprobar(propias >= (15 if nombre == "A" else 4), f"control positivo: {nombre} si ve filas propias ({propias} tablas)")

    # Funciones que cruzan iglesias: ni siquiera ejecutables
    for fn, cuerpo in (("exportar_iglesia", {"p_iglesia": otra}), ("adn_exportar_paquete", {"p_iglesia": otra}),
                       ("borrar_iglesia", {"p_iglesia": otra}), ("adn_borrar_suave", {"p_iglesia": otra, "p_actor": user, "p_motivo": "x"}),
                       ("adn_purgar_iglesia", {"p_iglesia": otra, "p_actor": user})):
        e, c = http("POST", f"/rpc/{fn}", tok, cuerpo)
        comprobar(e in (401, 403, 404), f"{nombre} no puede llamar a {fn} (estado {e})")

# Cifras: cada usuario ve solo las suyas
e, c = http("POST", "/rpc/adn_panel_inicio", jwt(USER_B), {})
comprobar(e == 200 and c["miembros"]["activos"] == 1 and not c["eventos_proximos"], f"el panel de B solo cuenta a B (estado {e})")
e, c = http("POST", "/rpc/adn_informe_miembros", jwt(USER_B), {})
comprobar(e == 200 and "Zoë" not in json.dumps(c, ensure_ascii=False), "el informe de miembros de B no contiene a nadie de A")

# Sin sesion
for t in tablas:
    e, c = http("GET", f"/{t}?select=iglesia_id&limit=1")
    comprobar(sin_filas(e, c), f"un visitante sin sesion no lee {t} (estado {e})")

comprobar(instantanea() == antes, "la base queda exactamente igual tras todos los ataques (filas y huellas por iglesia y tabla)")
print(f"{comprobaciones} comprobaciones, {len(fallos)} fallos")
sys.exit(1 if fallos else 0)
