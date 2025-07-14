#!/bin/bash

# ==============================================================================
# run_all_network_arch.sh: Script para Experimentos TCP/IP en Arch Linux
#
# Versión específica para Arch Linux que maneja mejor los procesos en segundo plano
#
# Uso:
#   En PC1 (servidor): ./run_all_network_arch.sh server
#   En PC2 (cliente):  ./run_all_network_arch.sh client [IP_DEL_PC1]
# ==============================================================================

set -e

# --- Configuración ---
BASE_DIR=$(pwd)
BIN_DIR="$BASE_DIR/bin"
TEST_DATA_DIR="$BASE_DIR/test_data"
RESULTS_DIR="$BASE_DIR/results/raw"
TEST_MOUNT="/mnt/ext4test"

# Parámetros de red
TCP_PORT=12345
DEFAULT_SERVER_IP="192.168.1.100" # Cambiar por la IP real del servidor

# Parámetros de prueba
REPETITIONS=10
FILE_SIZES_STR=("10M" "100M" "1G")
BUFFER_SIZES_KB=(4 64 1024)

# --- Funciones ---

drop_caches() {
    echo "--- Limpiando cachés de disco ---"
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    sleep 1
}

run_server_tests() {
    echo "=== EJECUTANDO COMO SERVIDOR (ARCH LINUX) ==="
    echo "Esperando conexiones en puerto $TCP_PORT..."
    echo "Asegúrate de que el cliente esté listo para conectarse."
    echo

    for (( i=1; i<=REPETITIONS; i++ )); do
        echo "********** REPETICIÓN $i/$REPETITIONS **********"
        
        for size_str in "${FILE_SIZES_STR[@]}"; do
            for bsize_kb in "${BUFFER_SIZES_KB[@]}"; do
                BSIZE_BYTES=$((bsize_kb * 1024))
                
                LOG_DIR="$RESULTS_DIR/tcp_socket/$size_str/${bsize_kb}KB/nosync/run_$i"
                mkdir -p "$LOG_DIR"
                OUTPUT_FILE="$TEST_MOUNT/output.dat"
                
                echo "-> Servidor TCP | Archivo: $size_str | Buffer: ${bsize_kb}KB | Rep: $i"
                drop_caches
                
                # Limpiar cualquier proceso anterior que pueda estar usando el puerto
                pkill -f "tcp_server.*$TCP_PORT" 2>/dev/null || true
                sleep 2
                
                # Ejecutar servidor con nohup para Arch Linux
                echo "Iniciando servidor TCP en puerto $TCP_PORT..."
                nohup /usr/bin/time -v strace -c -o "$LOG_DIR/strace_server.log" \
                    "$BIN_DIR/tcp_server" "$TCP_PORT" "$OUTPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_server.log" \
                    2> "$LOG_DIR/time_server.log" &
                SERVER_PID=$!
                
                echo "Servidor iniciado con PID: $SERVER_PID"
                
                # Verificar que el proceso realmente se inició
                sleep 3
                if ! kill -0 $SERVER_PID 2>/dev/null; then
                    echo "ERROR: El servidor no se inició correctamente"
                    echo "Logs del servidor:"
                    cat "$LOG_DIR/app_server.log" 2>/dev/null || echo "No hay logs disponibles"
                    continue
                fi
                
                echo "Servidor está ejecutándose correctamente"
                echo "Esperando conexión del cliente..."
                echo "El servidor está ejecutándose en segundo plano. Puedes ejecutar el cliente ahora."
                
                # Esperar a que el servidor termine (cuando el cliente se desconecte)
                wait $SERVER_PID 2>/dev/null || true
                SERVER_EXIT_CODE=$?
                
                if [ $SERVER_EXIT_CODE -eq 0 ]; then
                    echo "Transferencia completada exitosamente."
                else
                    echo "ERROR: El servidor terminó con código de salida $SERVER_EXIT_CODE"
                    echo "Logs del servidor:"
                    cat "$LOG_DIR/app_server.log" 2>/dev/null || echo "No hay logs disponibles"
                fi
                
                echo "Limpiando archivo de salida..."
                rm -f "$OUTPUT_FILE"
                echo "---"
                
                # Pausa entre pruebas para evitar problemas de puerto en uso
                sleep 3
            done
        done
    done
    
    echo "=== SERVIDOR FINALIZADO ==="
}

run_client_tests() {
    local SERVER_IP=${1:-$DEFAULT_SERVER_IP}
    
    echo "=== EJECUTANDO COMO CLIENTE (ARCH LINUX) ==="
    echo "Conectando al servidor en: $SERVER_IP:$TCP_PORT"
    echo

    for (( i=1; i<=REPETITIONS; i++ )); do
        echo "********** REPETICIÓN $i/$REPETITIONS **********"
        
        for size_str in "${FILE_SIZES_STR[@]}"; do
            INPUT_FILE="$TEST_DATA_DIR/file_${size_str}.dat"
            if [ ! -f "$INPUT_FILE" ]; then
                echo "AVISO: Archivo de prueba '$INPUT_FILE' no existe. Omitiendo."
                continue
            fi
            
            for bsize_kb in "${BUFFER_SIZES_KB[@]}"; do
                BSIZE_BYTES=$((bsize_kb * 1024))
                
                LOG_DIR="$RESULTS_DIR/tcp_socket/$size_str/${bsize_kb}KB/nosync/run_$i"
                mkdir -p "$LOG_DIR"
                
                echo "-> Cliente TCP | Archivo: $size_str | Buffer: ${bsize_kb}KB | Rep: $i"
                drop_caches
                
                echo "Conectando al servidor $SERVER_IP:$TCP_PORT..."
                # Ejecutar cliente
                /usr/bin/time -v strace -c -o "$LOG_DIR/strace_client.log" \
                    "$BIN_DIR/tcp_client" "$SERVER_IP" "$TCP_PORT" "$INPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_client.log" \
                    2> "$LOG_DIR/time_client.log"
                CLIENT_EXIT_CODE=$?
                
                if [ $CLIENT_EXIT_CODE -eq 0 ]; then
                    echo "Transferencia completada exitosamente."
                else
                    echo "ERROR: El cliente terminó con código de salida $CLIENT_EXIT_CODE"
                fi
                
                echo "---"
                
                # Pausa entre pruebas
                sleep 1
            done
        done
    done
    
    echo "=== CLIENTE FINALIZADO ==="
}

# --- Lógica Principal ---

if [ $# -eq 0 ]; then
    echo "Uso:"
    echo "  En PC1 (servidor): $0 server"
    echo "  En PC2 (cliente):  $0 client [IP_DEL_PC1]"
    echo
    echo "Ejemplo:"
    echo "  PC1: $0 server"
    echo "  PC2: $0 client 192.168.1.100"
    exit 1
fi

MODE=$1
SERVER_IP=$2

# Verificar que los binarios estén compilados
if [ ! -f "$BIN_DIR/tcp_server" ] || [ ! -f "$BIN_DIR/tcp_client" ]; then
    echo "ERROR: Los programas TCP no están compilados. Ejecute 'make' primero."
    exit 1
fi

# Verificar directorio de prueba
if [ ! -d "$TEST_MOUNT" ] || [ ! -w "$TEST_MOUNT" ]; then
    echo "ERROR: El directorio de prueba '$TEST_MOUNT' no existe o no tiene permisos."
    exit 1
fi

case $MODE in
    "server")
        run_server_tests
        ;;
    "client")
        if [ -z "$SERVER_IP" ]; then
            echo "ERROR: Debe especificar la IP del servidor."
            echo "Uso: $0 client [IP_DEL_PC1]"
            exit 1
        fi
        run_client_tests "$SERVER_IP"
        ;;
    *)
        echo "ERROR: Modo inválido. Use 'server' o 'client'."
        exit 1
        ;;
esac

echo "==============================================="
echo "       EXPERIMENTO DE RED COMPLETADO           "
echo "==============================================="
echo "Los resultados se encuentran en: $RESULTS_DIR"
echo "Para analizar, ejecute: python3 scripts/stats_parser.py" 