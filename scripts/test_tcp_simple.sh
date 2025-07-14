#!/bin/bash

# Script de prueba simple para Arch Linux minimal
# Uso: ./test_tcp_simple.sh

set -e

BASE_DIR=$(pwd)
BIN_DIR="$BASE_DIR/bin"
TEST_DATA_DIR="$BASE_DIR/test_data"
TEST_MOUNT="/mnt/ext4test"

TCP_PORT=12345
TEST_FILE="$TEST_DATA_DIR/file_10M.dat"
OUTPUT_FILE="$TEST_MOUNT/test_output.dat"

echo "=== PRUEBA SIMPLE TCP PARA ARCH LINUX MINIMAL ==="

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

# Limpiar procesos anteriores
echo "Limpiando procesos anteriores..."
pkill -f "tcp_server" 2>/dev/null || true
sleep 2

echo "Iniciando servidor TCP en puerto $TCP_PORT..."
echo "Archivo de entrada: $TEST_FILE"
echo "Archivo de salida: $OUTPUT_FILE"

# Iniciar servidor directamente (sin time/strace)
echo "Ejecutando: $BIN_DIR/tcp_server $TCP_PORT $OUTPUT_FILE 4096"
"$BIN_DIR/tcp_server" "$TCP_PORT" "$OUTPUT_FILE" 4096 > server.log 2>&1 &
SERVER_PID=$!

echo "Servidor iniciado con PID: $SERVER_PID"

# Verificar que el proceso se inició correctamente
sleep 3
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ERROR: El servidor no se inició correctamente"
    echo "Logs del servidor:"
    cat server.log 2>/dev/null || echo "No hay logs disponibles"
    exit 1
fi

echo "Servidor está ejecutándose correctamente"
echo "Esperando 3 segundos para que el servidor esté completamente listo..."
sleep 3

echo "Ejecutando cliente..."
echo "Ejecutando: $BIN_DIR/tcp_client 127.0.0.1 $TCP_PORT $TEST_FILE 4096"
"$BIN_DIR/tcp_client" "127.0.0.1" "$TCP_PORT" "$TEST_FILE" 4096 > client.log 2>&1
CLIENT_EXIT_CODE=$?

echo "Esperando a que el servidor termine..."
wait $SERVER_PID 2>/dev/null || true
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
    cat server.log 2>/dev/null || echo "No hay logs del servidor"
    echo "Logs del cliente:"
    cat client.log 2>/dev/null || echo "No hay logs del cliente"
fi

# Limpieza
rm -f "$OUTPUT_FILE" server.log client.log 2>/dev/null || true

echo "=== FIN DE PRUEBA ===" 