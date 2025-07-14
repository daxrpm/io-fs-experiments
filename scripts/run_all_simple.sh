#!/bin/bash

# ==============================================================================
# run_all_simple.sh: Script completo para Arch Linux minimal
#
# Ejecuta todas las pruebas (locales y de red) con mejor sincronización
# y guardado de datos para análisis posterior
#
# Uso:
#   Para pruebas locales: ./run_all_simple.sh local
#   Para pruebas de red: ./run_all_simple.sh network server|client [IP]
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
DEFAULT_SERVER_IP="192.168.1.100"

# Parámetros de prueba
REPETITIONS=10
FILE_SIZES_STR=("10M" "100M" "1G")
BUFFER_SIZES_KB=(4 64 1024)
SYNC_MODES=("nosync" "sync")

# --- Funciones ---

drop_caches() {
    echo "--- Limpiando cachés de disco ---"
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    sleep 1
}

run_local_tests() {
    echo "=== EJECUTANDO PRUEBAS LOCALES ==="
    echo "Fecha: $(date)"
    echo "Repeticiones: $REPETITIONS"
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
                
                # --- 1. Prueba: file_buffered ---
                for sync_mode in "${SYNC_MODES[@]}"; do
                    SYNC_FLAG=""
                    if [ "$sync_mode" == "sync" ]; then
                        SYNC_FLAG="--sync"
                    fi
                    
                    LOG_DIR="$RESULTS_DIR/buffered/$size_str/${bsize_kb}KB/$sync_mode/run_$i"
                    mkdir -p "$LOG_DIR"
                    OUTPUT_FILE="$TEST_MOUNT/output.dat"
                    
                    echo "-> Test: buffered | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: $sync_mode | Rep: $i"
                    drop_caches
                    
                    # Ejecutar con time para medir rendimiento
                    /usr/bin/time -v "$BIN_DIR/file_buffered" "$INPUT_FILE" "$OUTPUT_FILE" "$BSIZE_BYTES" $SYNC_FLAG > "$LOG_DIR/app.log" 2> "$LOG_DIR/time.log"
                    
                    rm -f "$OUTPUT_FILE"
                done

                # --- 2. Prueba: file_direct ---
                if (( BSIZE_BYTES % 512 == 0 )); then
                    for sync_mode in "${SYNC_MODES[@]}"; do
                        SYNC_FLAG=""
                        if [ "$sync_mode" == "sync" ]; then
                            SYNC_FLAG="--sync"
                        fi
                        
                        LOG_DIR="$RESULTS_DIR/direct/$size_str/${bsize_kb}KB/$sync_mode/run_$i"
                        mkdir -p "$LOG_DIR"
                        OUTPUT_FILE="$TEST_MOUNT/output.dat"
                        
                        echo "-> Test: direct   | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: $sync_mode | Rep: $i"
                        drop_caches
                        
                        /usr/bin/time -v "$BIN_DIR/file_direct" "$INPUT_FILE" "$OUTPUT_FILE" "$BSIZE_BYTES" $SYNC_FLAG > "$LOG_DIR/app.log" 2> "$LOG_DIR/time.log"
                        
                        rm -f "$OUTPUT_FILE"
                    done
                fi

                # --- 3. Prueba: file_sendfile ---
                if [ $bsize_kb -eq 4 ]; then
                    for sync_mode in "${SYNC_MODES[@]}"; do
                        SYNC_FLAG=""
                        if [ "$sync_mode" == "sync" ]; then
                            SYNC_FLAG="--sync"
                        fi
                        
                        LOG_DIR="$RESULTS_DIR/sendfile/$size_str/0KB/$sync_mode/run_$i"
                        mkdir -p "$LOG_DIR"
                        OUTPUT_FILE="$TEST_MOUNT/output.dat"

                        echo "-> Test: sendfile | Archivo: $size_str | Buffer: N/A | Sync: $sync_mode | Rep: $i"
                        drop_caches
                        
                        /usr/bin/time -v "$BIN_DIR/file_sendfile" "$INPUT_FILE" "$OUTPUT_FILE" $SYNC_FLAG > "$LOG_DIR/app.log" 2> "$LOG_DIR/time.log"
                        
                        rm -f "$OUTPUT_FILE"
                    done
                fi

                # --- 4. Prueba: UNIX Sockets ---
                LOG_DIR="$RESULTS_DIR/unix_socket/$size_str/${bsize_kb}KB/nosync/run_$i"
                mkdir -p "$LOG_DIR"
                OUTPUT_FILE="$TEST_MOUNT/output.dat"
                UNIX_SOCKET_PATH="$TEST_MOUNT/test_socket.sock"

                echo "-> Test: unix     | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: N/A | Rep: $i"
                drop_caches
                
                # Iniciar servidor en segundo plano
                "$BIN_DIR/unix_socket_server" "$UNIX_SOCKET_PATH" "$OUTPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_server.log" 2>&1 &
                SERVER_PID=$!
                sleep 2
                
                # Ejecutar cliente
                /usr/bin/time -v "$BIN_DIR/unix_socket_client" "$UNIX_SOCKET_PATH" "$INPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app.log" 2> "$LOG_DIR/time.log"
                
                wait $SERVER_PID || true
                rm -f "$OUTPUT_FILE" "$UNIX_SOCKET_PATH"
            done
        done
    done
    
    echo "=== PRUEBAS LOCALES COMPLETADAS ==="
}

run_network_server() {
    echo "=== EJECUTANDO COMO SERVIDOR TCP ==="
    echo "Esperando conexiones en puerto $TCP_PORT..."
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
                
                # Limpiar procesos anteriores
                pkill -f "tcp_server" 2>/dev/null || true
                sleep 3
                
                echo "Iniciando servidor TCP en puerto $TCP_PORT..."
                
                # Ejecutar servidor con time para medir rendimiento
                /usr/bin/time -v "$BIN_DIR/tcp_server" "$TCP_PORT" "$OUTPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_server.log" 2>&1 &
                SERVER_PID=$!
                
                echo "Servidor iniciado con PID: $SERVER_PID"
                
                # Verificar que el proceso se inició
                sleep 5
                if ! kill -0 $SERVER_PID 2>/dev/null; then
                    echo "ERROR: El servidor no se inició correctamente"
                    cat "$LOG_DIR/app_server.log" 2>/dev/null || echo "No hay logs disponibles"
                    continue
                fi
                
                echo "Servidor está ejecutándose. Esperando conexión del cliente..."
                echo "Esperando 30 segundos para que el cliente se conecte..."
                
                # Esperar a que el servidor termine con timeout
                timeout 30 wait $SERVER_PID 2>/dev/null || true
                SERVER_EXIT_CODE=$?
                
                if [ $SERVER_EXIT_CODE -eq 0 ]; then
                    echo "Transferencia completada exitosamente."
                else
                    echo "ERROR: El servidor terminó con código de salida $SERVER_EXIT_CODE"
                fi
                
                rm -f "$OUTPUT_FILE"
                echo "---"
                sleep 5
            done
        done
    done
    
    echo "=== SERVIDOR FINALIZADO ==="
}

run_network_client() {
    local SERVER_IP=${1:-$DEFAULT_SERVER_IP}
    
    echo "=== EJECUTANDO COMO CLIENTE TCP ==="
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
                
                echo "Esperando 3 segundos para que el servidor esté listo..."
                sleep 3
                
                echo "Conectando al servidor $SERVER_IP:$TCP_PORT..."
                
                # Ejecutar cliente con time para medir rendimiento
                timeout 30 /usr/bin/time -v "$BIN_DIR/tcp_client" "$SERVER_IP" "$TCP_PORT" "$INPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_client.log" 2> "$LOG_DIR/time_client.log"
                CLIENT_EXIT_CODE=$?
                
                if [ $CLIENT_EXIT_CODE -eq 0 ]; then
                    echo "Transferencia completada exitosamente."
                elif [ $CLIENT_EXIT_CODE -eq 124 ]; then
                    echo "ERROR: Timeout - el cliente tardó demasiado en conectarse"
                else
                    echo "ERROR: El cliente terminó con código de salida $CLIENT_EXIT_CODE"
                fi
                
                echo "---"
                sleep 2
            done
        done
    done
    
    echo "=== CLIENTE FINALIZADO ==="
}

# --- Lógica Principal ---

if [ $# -eq 0 ]; then
    echo "Uso:"
    echo "  Para pruebas locales: $0 local"
    echo "  Para pruebas de red: $0 network server|client [IP]"
    echo
    echo "Ejemplos:"
    echo "  $0 local"
    echo "  $0 network server"
    echo "  $0 network client 192.168.1.100"
    exit 1
fi

MODE=$1

# Verificar que los binarios estén compilados
if [ ! -f "$BIN_DIR/file_buffered" ] || [ ! -f "$BIN_DIR/tcp_server" ]; then
    echo "ERROR: Los programas no están compilados. Ejecute 'make' primero."
    exit 1
fi

# Verificar directorio de prueba
if [ ! -d "$TEST_MOUNT" ] || [ ! -w "$TEST_MOUNT" ]; then
    echo "ERROR: El directorio de prueba '$TEST_MOUNT' no existe o no tiene permisos."
    exit 1
fi

case $MODE in
    "local")
        run_local_tests
        ;;
    "network")
        if [ $# -lt 2 ]; then
            echo "ERROR: Debe especificar 'server' o 'client' para modo network."
            exit 1
        fi
        
        NETWORK_MODE=$2
        SERVER_IP=$3
        
        case $NETWORK_MODE in
            "server")
                run_network_server
                ;;
            "client")
                if [ -z "$SERVER_IP" ]; then
                    echo "ERROR: Debe especificar la IP del servidor."
                    echo "Uso: $0 network client [IP_DEL_PC1]"
                    exit 1
                fi
                run_network_client "$SERVER_IP"
                ;;
            *)
                echo "ERROR: Modo de red inválido. Use 'server' o 'client'."
                exit 1
                ;;
        esac
        ;;
    *)
        echo "ERROR: Modo inválido. Use 'local' o 'network'."
        exit 1
        ;;
esac

echo "==============================================="
echo "       EXPERIMENTO COMPLETADO CON ÉXITO        "
echo "==============================================="
echo "Los resultados se encuentran en: $RESULTS_DIR"
echo "Para analizar, ejecute: python3 scripts/stats_parser.py" 