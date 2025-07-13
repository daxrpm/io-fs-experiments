#!/bin/bash

# Script de prueba simple para TCP server/client
# Uso: ./test_tcp.sh

set -e

BASE_DIR=$(pwd)
BIN_DIR="$BASE_DIR/bin"
TEST_DATA_DIR="$BASE_DIR/test_data"
TEST_MOUNT="/mnt/ext4test"

TCP_PORT=12345
TEST_FILE="$TEST_DATA_DIR/file_10M.dat"
OUTPUT_FILE="$TEST_MOUNT/test_output.dat"

echo "=== PRUEBA SIMPLE DE TCP SERVER/CLIENT ==="

# Verificar que los binarios existen
if [ ! -f "$BIN_DIR/tcp_server" ] || [ ! -f "$BIN_DIR/tcp_client" ]; then
    echo "ERROR: Los programas TCP no están compilados. Ejecute 'make' primero."
    exit 1
fi

# Verificar que el archivo de prueba existe
if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: El archivo de prueba '$TEST_FILE' no existe."
    echo "Ejecute: ./test_data/generate_files.sh"
    exit 1
fi

# Verificar directorio de prueba
if [ ! -d "$TEST_MOUNT" ] || [ ! -w "$TEST_MOUNT" ]; then
    echo "ERROR: El directorio de prueba '$TEST_MOUNT' no existe o no tiene permisos."
    exit 1
fi

echo "Iniciando servidor TCP en puerto $TCP_PORT..."
echo "Archivo de entrada: $TEST_FILE"
echo "Archivo de salida: $OUTPUT_FILE"

# Iniciar servidor en segundo plano
"$BIN_DIR/tcp_server" "$TCP_PORT" "$OUTPUT_FILE" 4096 > server.log 2>&1 &
SERVER_PID=$!

echo "Servidor iniciado con PID: $SERVER_PID"
echo "Esperando 2 segundos para que el servidor esté listo..."
sleep 2

echo "Ejecutando cliente..."
"$BIN_DIR/tcp_client" "127.0.0.1" "$TCP_PORT" "$TEST_FILE" 4096 > client.log 2>&1
CLIENT_EXIT_CODE=$?

echo "Esperando a que el servidor termine..."
wait $SERVER_PID
SERVER_EXIT_CODE=$?

echo "=== RESULTADOS ==="
echo "Cliente terminó con código: $CLIENT_EXIT_CODE"
echo "Servidor terminó con código: $SERVER_EXIT_CODE"

if [ $CLIENT_EXIT_CODE -eq 0 ] && [ $SERVER_EXIT_CODE -eq 0 ]; then
    echo "✅ PRUEBA EXITOSA"
    
    # Verificar que el archivo de salida se creó correctamente
    if [ -f "$OUTPUT_FILE" ]; then
        INPUT_SIZE=$(stat -c%s "$TEST_FILE")
        OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
        echo "Tamaño archivo entrada: $INPUT_SIZE bytes"
        echo "Tamaño archivo salida: $OUTPUT_SIZE bytes"
        
        if [ $INPUT_SIZE -eq $OUTPUT_SIZE ]; then
            echo "✅ Los archivos tienen el mismo tamaño"
        else
            echo "❌ ERROR: Los archivos tienen tamaños diferentes"
        fi
    else
        echo "❌ ERROR: No se creó el archivo de salida"
    fi
else
    echo "❌ PRUEBA FALLIDA"
    echo "Logs del servidor:"
    cat server.log
    echo "Logs del cliente:"
    cat client.log
fi

# Limpieza
rm -f "$OUTPUT_FILE" server.log client.log

echo "=== FIN DE PRUEBA ===" 