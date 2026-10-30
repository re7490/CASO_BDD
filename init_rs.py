import time
from pymongo import MongoClient

# Conexión directa al primer nodo para inicializar
client = MongoClient(
    "mongodb://mongo1:30001,mongo2:30002,mongo3:30003/?replicaSet=my-replica-set"
)
admin_db = client.admin

config = {
    "_id": "my-replica-set",
    "members": [
        {"_id": 0, "host": "mongo1:30001", "priority": 2},
        {"_id": 1, "host": "mongo2:30002", "priority": 1},
        {"_id": 2, "host": "mongo3:30003", "priority": 1}
    ]
}

try:
    print("Iniciando Replica Set...")
    admin_db.command("replSetInitiate", config)
    print("¡Replica Set inicializado con éxito!")
except Exception as e:
    print(f"Aviso / Estado previo: {e}")

time.sleep(5)

status = admin_db.command("replSetGetStatus")
print("\nMiembros del clúster:")
for m in status["members"]:
    print(f"Nodo: {m['name']} -> Estado: {m['stateStr']}")