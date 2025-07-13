#!/bin/bash

# Este script genera los archivos de datos necesarios para los experimentos.
# Se crearán archivos de 10MB, 100MB y 1GB.
#
# Uso: bash generate_files.sh

# Directorio donde se guardarán los archivos de prueba
# Se asume que el script se ejecuta desde la raíz del proyecto.
DATA_DIR="test_data"

# Tamaños de archivo
SIZES=("10M" "100M" "1G")
BLOCK_SIZE="1M"

# Crear el directorio si no existe
mkdir -p $DATA_DIR

echo "Generando archivos de prueba en el directorio '$DATA_DIR'..."

for size in "${SIZES[@]}"; do
    output_file="$DATA_DIR/file_${size}.dat"
    # Extraer el número del tamaño (ej. 10 de "10M")
    count=$(echo $size | sed 's/[A-Za-z]//g')

    echo "Creando archivo: $output_file ($size)..."
    if [ -f "$output_file" ]; then
        echo "El archivo $output_file ya existe, se omitirá."
    else
        # Usamos /dev/urandom para contenido aleatorio, lo que evita que
        # la compresión del sistema de archivos afecte los resultados.
        dd if=/dev/urandom of=$output_file bs=$BLOCK_SIZE count=$count iflag=fullblock status=progress
        if [ $? -eq 0 ]; then
            echo "Archivo $output_file creado exitosamente."
        else
            echo "Error al crear el archivo $output_file."
            exit 1
        fi
    fi
done

echo "Todos los archivos de prueba han sido generados."
ls -lh $DATA_DIR 