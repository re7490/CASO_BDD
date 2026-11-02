Tarea 3/CASO -- Base de Datos

Integrantes:

    Elias Palma -- Rol: 202473625-6 
    Renato Padilla -- Rol: 202473641-8

Adjunto a este README viene lo siguiente: 
    - Carpeta PDF:  
    - Carpeta JSON: 
    - Carpeta BD: 
    - Archivo deploy-2024736256-2024736418:
    - Archivo pymongo-2024736256-2024736418 

Pasos para iniciar el proyecto:

REQUISITOS PREVIOS:

* Docker Desktop en ejecución (con integración de WSL2 activa en Settings -> Resources -> WSL Integration).

* MySQL Server instalado y corriendo localmente en el entorno WSL2/Linux.

* Python 3.10+ instalado en el entorno.


1. Asociar los nombres de dominio del Replica Set a localhost en el sistema WSL2:

   echo "127.0.0.1 mongo1 mongo2 mongo3" | sudo tee -a /etc/hosts

   (Comprobación: ejecutar 'cat /etc/hosts | grep mongo' y verificar que devuelva
    '127.0.0.1 mongo1 mongo2 mongo3').

2. Crear y activar el entorno virtual:

   python3 -m venv .venv
   source .venv/bin/activate

3. Instalar las librerías necesarias:

   pip install pymongo mysql-connector-python pandas jupyter

4. Asegurarse de que el servicio MySQL esté corriendo:

   sudo service mysql start

5. Importar el script SQL que contiene el esquema y los datos:

   mysql -u root -p saludusm < BD/salud_usm.sql
   (Si root no tiene contraseña asignada, ejecutar sin '-p':
    mysql -u root saludusm < BD/salud_usm.sql).

6. Iniciar los 3 nodos de MongoDB en segundo plano:

   docker compose -f deploy-2024736256-2024736418.yml up -d

7. Esperar 10 segundos para que los procesos de mongod arranquen completamente.

8. Inicializar el Replica Set desde el contenedor mongo1:

    docker exec -it mongo1 mongosh --port 30001 --eval 'rs.initiate({

    _id: "my-replica-set",

    members: [
        { _id: 0, host: "mongo1:30001", priority: 2 },
        { _id: 1, host: "mongo2:30002", priority: 1 },
        { _id: 2, host: "mongo3:30003", priority: 1 }
    ]
})'


    (La salida esperada debe incluir '{ ok: 1 }').


9. Esperar 5 a 8 segundos a que concluya la votación y verificar los roles:

   docker exec -it mongo1 mongosh --port 30001 --eval 'rs.status().members.map(m => ({name: m.name, stateStr: m.stateStr}))'

   (Debe mostrar un nodo en PRIMARY y dos nodos en SECONDARY).

10. Ejecutar el script de migración y validación cruzada:

    python3 BD/migracion.py

11. Verificar que la tabla comparativa final arroje coincidencia exacta 1:1:

   * centros_medicos:       4
   * especialidades:        8
   * previsiones:           3
   * medicos:               16
   * pacientes:             42
   * citas:                 131
   * atenciones (anidadas): 64
   * recetas (anidadas):    86

12. Ejecutar el notebook con runall.

Alt + z <---- Recomendacion