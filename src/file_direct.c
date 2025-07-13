#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <malloc.h> // Para memalign/posix_memalign

/**
 * file_direct.c
 *
 * Realiza una copia de archivo utilizando E/S directa (sin buffer de S.O.).
 * Este programa utiliza la bandera O_DIRECT de open() para instruir al kernel
 * que evite el cache de página. Las lecturas y escrituras se realizan
 * directamente entre el buffer de usuario y el dispositivo.
 *
 * Referencia teórica: Stallings, Cap. 11.4. Aunque O_DIRECT no es un
 * "buffer-less I/O" puro (el hardware tiene sus propios caches), es el
 * mecanismo estándar en POSIX para minimizar el caching del S.O. y permitir
 * que las aplicaciones gestionen su propia estrategia de cache. Requiere
 * alineación de memoria y tamaño para los buffers.
 *
 * Argumentos:
 *  - <fichero_entrada>: Ruta al archivo de origen.
 *  - <fichero_salida>: Ruta al archivo de destino.
 *  - <tam_buffer>: Tamaño del búfer (debe ser múltiplo del tamaño de bloque del FS).
 *  - [--sync]: Opcional. Aunque O_DIRECT implica E/S síncrona, fsync()
 *              garantiza la escritura de metadatos.
 */

#define ALIGNMENT 512 // Alineación de 512 bytes, común para O_DIRECT

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <fichero_entrada> <fichero_salida> <tam_buffer> [--sync]\n", prog_name);
    fprintf(stderr, "Nota: tam_buffer debe ser múltiplo de %d.\n", ALIGNMENT);
}

int main(int argc, char *argv[]) {
    if (argc < 4 || argc > 5) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *input_path = argv[1];
    const char *output_path = argv[2];
    long buffer_size = atol(argv[3]);
    int use_fsync = (argc == 5 && strcmp(argv[4], "--sync") == 0);

    if (buffer_size <= 0 || buffer_size % ALIGNMENT != 0) {
        fprintf(stderr, "Error: El tamaño del buffer debe ser un múltiplo de %d.\n", ALIGNMENT);
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    // --- Apertura de archivos con O_DIRECT ---
    // O_DIRECT requiere que las operaciones de E/S estén alineadas.
    int fd_in = open(input_path, O_RDONLY | O_DIRECT);
    if (fd_in == -1) {
        perror("Error al abrir el archivo de entrada con O_DIRECT");
        exit(EXIT_FAILURE);
    }

    int fd_out = open(output_path, O_WRONLY | O_CREAT | O_TRUNC | O_DIRECT, 0644);
    if (fd_out == -1) {
        perror("Error al abrir el archivo de salida con O_DIRECT");
        close(fd_in);
        exit(EXIT_FAILURE);
    }

    // --- Asignación del búfer alineado ---
    void *buffer;
    int ret = posix_memalign(&buffer, ALIGNMENT, buffer_size);
    if (ret != 0) {
        errno = ret;
        perror("Error en posix_memalign");
        close(fd_in);
        close(fd_out);
        exit(EXIT_FAILURE);
    }

    // --- Medición de tiempo y copia ---
    struct timespec start, end;
    long read_calls = 0;
    long write_calls = 0;
    ssize_t bytes_read;

    clock_gettime(CLOCK_MONOTONIC, &start);

    while ((bytes_read = read(fd_in, buffer, buffer_size)) > 0) {
        read_calls++;
        // Con O_DIRECT, la escritura debe tener un tamaño múltiplo del tamaño de bloque,
        // excepto posiblemente la última escritura. Aquí asumimos que las lecturas no finales
        // serán del tamaño completo del buffer.
        ssize_t bytes_written = write(fd_out, buffer, bytes_read);
        write_calls++;
        if (bytes_written != bytes_read) {
            perror("Error de escritura incompleta");
            free(buffer);
            close(fd_in);
            close(fd_out);
            exit(EXIT_FAILURE);
        }
    }

    if (bytes_read == -1) {
        perror("Error de lectura");
        free(buffer);
        close(fd_in);
        close(fd_out);
        exit(EXIT_FAILURE);
    }
    
    if (use_fsync) {
        if (fsync(fd_out) == -1) {
            perror("Error en fsync");
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    
    // --- Cálculo de tiempo y resultados ---
    double time_taken = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;

    // --- Limpieza ---
    free(buffer);
    close(fd_in);
    close(fd_out);

    // --- Imprimir resultados para el parser ---
    printf("Mechanism: Direct I/O\n");
    printf("BufferSize: %ld\n", buffer_size);
    printf("SyncMode: %s\n", use_fsync ? "sync" : "nosync");
    printf("TimeTaken: %.6f\n", time_taken);
    printf("ReadCalls: %ld\n", read_calls);
    printf("WriteCalls: %ld\n", write_calls);

    return 0;
} 