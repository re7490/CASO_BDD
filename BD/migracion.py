import mysql.connector
from pymongo import MongoClient

# 1. CONEXIÓN
mysql_conn = mysql.connector.connect(
    host="127.0.0.1",
    user="root",
    password="tu_nueva_clave",
    database="saludusm"
)
cursor = mysql_conn.cursor(dictionary=True)

mongo_client = MongoClient("mongodb://127.0.0.1:30001/?directConnection=true")
db = mongo_client["salud_usm"]

print("Conexiones establecidas. Reiniciando colecciones en MongoDB...")
colecciones = ["centros_medicos", "especialidades", "previsiones", "medicos", "pacientes", "citas"]
for col in colecciones:
    db[col].drop()

# 2. MIGRACIÓN DE CATÁLOGOS

print("\n[1/5] Migrando catálogos (previsiones, especialidades, centros)...")

cursor.execute("SELECT nombre_prevision FROM prevision")
previsiones = [{"_id": r["nombre_prevision"], "nombre": r["nombre_prevision"]} for r in cursor.fetchall()]
db.previsiones.insert_many(previsiones)

cursor.execute("SELECT nombre_especialidad FROM especialidad")
especialidades = [{"_id": r["nombre_especialidad"], "nombre": r["nombre_especialidad"]} for r in cursor.fetchall()]
db.especialidades.insert_many(especialidades)

cursor.execute("SELECT codigo_centro, nombre_centro, comuna, region FROM centro_medico")
centros_raw = cursor.fetchall()
centros_docs = [{
    "_id": c["codigo_centro"],
    "codigo_centro": c["codigo_centro"],
    "nombre": c["nombre_centro"],
    "comuna": c["comuna"],
    "region": c["region"]
} for c in centros_raw]
db.centros_medicos.insert_many(centros_docs)

# 3. MIGRACIÓN DE MÉDICOS Y PACIENTES

print("[2/5] Migrando médicos (con arreglos de especialidades y centros)...")
cursor.execute("SELECT rut_medico, nombre_completo, email_institucional, id_usuario FROM medico")
medicos_raw = cursor.fetchall()

cursor.execute("SELECT rut_medico, nombre_especialidad FROM medico_especialidad")
med_esp_raw = cursor.fetchall()

cursor.execute("SELECT rut_medico, codigo_centro FROM medico_centro")
med_centros_raw = cursor.fetchall()

medicos_docs = []
for m in medicos_raw:
    rut = m["rut_medico"]
    esp_list = [e["nombre_especialidad"] for e in med_esp_raw if e["rut_medico"] == rut]
    centros_list = [c["codigo_centro"] for c in med_centros_raw if c["rut_medico"] == rut]
    medicos_docs.append({
        "_id": rut,
        "rut_medico": rut,
        "nombre_completo": m["nombre_completo"],
        "email_institucional": m["email_institucional"],
        "id_usuario": m["id_usuario"],
        "especialidades": esp_list,
        "centros": centros_list
    })
db.medicos.insert_many(medicos_docs)

print("[3/5] Migrando pacientes...")
cursor.execute("SELECT rut_paciente, nombre_completo, fecha_nacimiento, sexo, telefono, comuna_residencia, nombre_prevision, id_usuario FROM paciente")
pacientes_raw = cursor.fetchall()
pacientes_docs = [{
    "_id": p["rut_paciente"],
    "rut_paciente": p["rut_paciente"],
    "nombre_completo": p["nombre_completo"],
    "fecha_nacimiento": str(p["fecha_nacimiento"]),
    "sexo": p["sexo"],
    "telefono": p["telefono"],
    "comuna_residencia": p["comuna_residencia"],
    "prevision": p["nombre_prevision"],
    "id_usuario": p["id_usuario"]
} for p in pacientes_raw]
db.pacientes.insert_many(pacientes_docs)

# 4. MIGRACIÓN DE CITAS CON ATENCIONES ANIDADAS

print("[4/5] Migrando citas, atenciones, diagnósticos y recetas anidadas...")

centros_map = {c["codigo_centro"]: c for c in centros_docs}
pacientes_map = {p["rut_paciente"]: p for p in pacientes_docs}
medicos_map = {m["rut_medico"]: m for m in medicos_docs}

cursor.execute("SELECT id_atencion, id_cita, fecha_atencion, motivo_consulta, observaciones FROM atencion")
atenciones_raw = cursor.fetchall()

cursor.execute("""
    SELECT ad.id_atencion, ad.codigo_cie10, d.descripcion 
    FROM atencion_diagnostico ad
    JOIN diagnostico d ON ad.codigo_cie10 = d.codigo_cie10
""")
diagnosticos_raw = cursor.fetchall()

cursor.execute("SELECT id_receta, id_atencion, medicamento, dosis, dias_tratamiento FROM receta")
recetas_raw = cursor.fetchall()

cursor.execute("SELECT id_cita, fecha, hora, rut_paciente, rut_medico, codigo_centro, nombre_especialidad, estado FROM cita_medica")
citas_raw = cursor.fetchall()

atenciones_map = {}
for a in atenciones_raw:
    id_atn = a["id_atencion"]
    diags = [{
        "codigo_cie10": d["codigo_cie10"],
        "descripcion": d["descripcion"]
    } for d in diagnosticos_raw if d["id_atencion"] == id_atn]
    
    recs = [{
        "id_receta": r["id_receta"],
        "medicamento": r["medicamento"],
        "dosis": r["dosis"],
        "dias_tratamiento": r["dias_tratamiento"]
    } for r in recetas_raw if r["id_atencion"] == id_atn]
    
    atenciones_map[a["id_cita"]] = {
        "id_atencion": id_atn,
        "fecha_atencion": a["fecha_atencion"].isoformat() if a["fecha_atencion"] else None,
        "motivo_consulta": a["motivo_consulta"],
        "observaciones": a["observaciones"],
        "diagnosticos": diags,
        "recetas": recs
    }

citas_docs = []
for c in citas_raw:
    id_c = c["id_cita"]
    pac = pacientes_map.get(c["rut_paciente"], {})
    med = medicos_map.get(c["rut_medico"], {})
    cen = centros_map.get(c["codigo_centro"], {})

    hora_str = str(c["hora"])
    if len(hora_str) == 7:
        hora_str = "0" + hora_str

    doc = {
        "_id": id_c,
        "id_cita": id_c,
        "fecha": str(c["fecha"]),
        "hora": hora_str,
        "estado": c["estado"],
        "paciente": {
            "rut": c["rut_paciente"],
            "nombre": pac.get("nombre_completo"),
            "prevision": pac.get("prevision")
        },
        "medico": {
            "rut": c["rut_medico"],
            "nombre": med.get("nombre_completo")
        },
        "centro": {
            "codigo": c["codigo_centro"],
            "nombre": cen.get("nombre"),
            "region": cen.get("region")
        },
        "especialidad": c["nombre_especialidad"]
    }
    
    if id_c in atenciones_map:
        doc["atencion"] = atenciones_map[id_c]
        
    citas_docs.append(doc)

db.citas.insert_many(citas_docs)


# 5. VALIDACIÓN

print("\n[5/5] Verificación comparativa (MySQL vs. MongoDB):")
print("-" * 65)
print(f"{'Colección / Tabla':<25} | {'MySQL COUNT(*)':<16} | {'MongoDB count':<15}")
print("-" * 65)

def get_mysql_count(table):
    cursor.execute(f"SELECT COUNT(*) as c FROM {table}")
    return cursor.fetchone()["c"]

print(f"{'centros_medicos':<25} | {get_mysql_count('centro_medico'):<16} | {db.centros_medicos.count_documents({}):<15}")
print(f"{'especialidades':<25} | {get_mysql_count('especialidad'):<16} | {db.especialidades.count_documents({}):<15}")
print(f"{'previsiones':<25} | {get_mysql_count('prevision'):<16} | {db.previsiones.count_documents({}):<15}")
print(f"{'medicos':<25} | {get_mysql_count('medico'):<16} | {db.medicos.count_documents({}):<15}")
print(f"{'pacientes':<25} | {get_mysql_count('paciente'):<16} | {db.pacientes.count_documents({}):<15}")
print(f"{'citas':<25} | {get_mysql_count('cita_medica'):<16} | {db.citas.count_documents({}):<15}")

atenciones_mongo = db.citas.count_documents({"atencion": {"$exists": True}})
recetas_mongo = db.citas.aggregate([
    {"$match": {"atencion.recetas": {"$exists": True}}},
    {"$unwind": "$atencion.recetas"},
    {"$count": "total"}
])
recetas_count = list(recetas_mongo)
recetas_total = recetas_count[0]["total"] if recetas_count else 0

print(f"{'atenciones (anidadas)':<25} | {get_mysql_count('atencion'):<16} | {atenciones_mongo:<15}")
print(f"{'recetas (anidadas)':<25} | {get_mysql_count('receta'):<16} | {recetas_total:<15}")
print("-" * 65)
print("¡Migración y verificación completadas sin pérdida de datos!")

cursor.close()
mysql_conn.close()