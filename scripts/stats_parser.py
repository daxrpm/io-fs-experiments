#!/usr/bin/env python3

"""
stats_parser.py

Analiza los resultados crudos generados por 'run_all.sh', calcula estadísticas
y genera un resumen en CSV junto con gráficos comparativos.

Este script es el paso final del experimento, transformando los logs en
datos estructurados y visualizaciones para el análisis de rendimiento.
"""

import os
import re
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import sys

# --- Constantes y Configuración ---
BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAW_RESULTS_DIR = os.path.join(BASE_DIR, "results", "raw")
FINAL_RESULTS_DIR = os.path.join(BASE_DIR, "results")
CHARTS_DIR = os.path.join(FINAL_RESULTS_DIR, "charts")
SUMMARY_CSV_PATH = os.path.join(FINAL_RESULTS_DIR, "summary.csv")

# Asegurarse de que el directorio de gráficos exista
os.makedirs(CHARTS_DIR, exist_ok=True)

# --- Funciones de Parsing ---

def parse_time_log(file_path):
    """Parsea el output de /usr/bin/time -v."""
    metrics = {}
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            
            # Wall clock time
            match = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (.*?)\n', content)
            if match:
                time_str = match.group(1)
                parts = list(map(float, time_str.split(':')))
                if len(parts) == 3: # h:mm:ss.ss
                    metrics['time_elapsed_s'] = parts[0] * 3600 + parts[1] * 60 + parts[2]
                elif len(parts) == 2: # m:ss.ss
                    metrics['time_elapsed_s'] = parts[0] * 60 + parts[1]
            
            # User/System time y CPU
            match = re.search(r'User time \(seconds\): (.*?)\n', content)
            if match: metrics['time_user_s'] = float(match.group(1))
            
            match = re.search(r'System time \(seconds\): (.*?)\n', content)
            if match: metrics['time_system_s'] = float(match.group(1))

            match = re.search(r'Percent of CPU this job got: (.*?)%\n', content)
            if match: metrics['cpu_percent'] = float(match.group(1))
            
    except (IOError, ValueError):
        # Ignorar si el archivo no existe o tiene formato incorrecto
        pass
    return metrics

def parse_strace_log(file_path):
    """Parsea el output de strace -c."""
    syscalls = {}
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
            # Buscar la línea de cabecera para empezar a parsear desde ahí
            header_found = False
            for line in lines:
                if 'calls' in line and 'syscall' in line:
                    header_found = True
                    continue
                if header_found and '---' not in line and line.strip():
                    parts = line.split()
                    if len(parts) >= 5:
                        syscall_name = parts[-1]
                        calls = int(parts[-2])
                        syscalls[f'syscall_{syscall_name}'] = calls
    except (IOError, IndexError):
        pass
    return syscalls

def parse_app_log(file_path):
    """Parsea el output custom de los programas en C."""
    app_metrics = {}
    try:
        with open(file_path, 'r') as f:
            for line in f:
                if ':' in line:
                    key, value = line.split(':', 1)
                    app_metrics[key.strip()] = value.strip()
    except IOError:
        pass
    return app_metrics

def get_file_size_bytes(size_str):
    """Convierte un string como '10M' a bytes."""
    size_map = {'K': 1024, 'M': 1024**2, 'G': 1024**3}
    match = re.match(r'(\d+)', size_str)
    if not match:
        return 0
    num = int(match.group(1))
    unit = size_str[-1].upper()
    return num * size_map.get(unit, 1)


# --- Proceso Principal ---

def main():
    """Función principal que orquesta el parsing, análisis y generación de output."""
    print("Iniciando análisis de resultados...")
    
    all_data = []

    if not os.path.exists(RAW_RESULTS_DIR):
        print(f"ERROR: El directorio de resultados crudos '{RAW_RESULTS_DIR}' no existe.")
        print("Asegúrate de haber ejecutado 'scripts/run_all.sh' primero.")
        sys.exit(1)

    # Recorrer el árbol de directorios de resultados
    for root, _, files in os.walk(RAW_RESULTS_DIR):
        if 'time.log' in files:
            # Extraer parámetros desde la ruta
            path_parts = root.replace(RAW_RESULTS_DIR, '').strip(os.sep).split(os.sep)
            if len(path_parts) != 5: continue
            
            mechanism, file_size_str, buffer_size_str, sync_mode, run_id = path_parts
            
            run_data = {
                'mechanism': mechanism,
                'file_size': file_size_str,
                'buffer_size_kb': int(buffer_size_str.replace('KB', '')),
                'sync_mode': sync_mode,
                'run': int(run_id.replace('run_', ''))
            }
            
            # Parsear todos los logs para esta ejecución
            run_data.update(parse_time_log(os.path.join(root, 'time.log')))
            run_data.update(parse_strace_log(os.path.join(root, 'strace.log')))
            run_data.update(parse_app_log(os.path.join(root, 'app.log')))
            
            all_data.append(run_data)

    if not all_data:
        print("No se encontraron datos de logs para analizar.")
        return

    # Convertir a DataFrame de Pandas
    df = pd.DataFrame(all_data)

    # --- Limpieza y Cálculo de Métricas Derivadas ---
    df['file_size_bytes'] = df['file_size'].apply(get_file_size_bytes)
    
    # El tiempo medido por nuestra app es más preciso que el wall-clock de 'time'
    # Usamos el tiempo de la app si está disponible, si no, el de 'time'
    df['TimeTaken'] = pd.to_numeric(df['TimeTaken'], errors='coerce')
    df['TimeTakenClient'] = pd.to_numeric(df['TimeTakenClient'], errors='coerce')
    df['time_s'] = df['TimeTaken'].fillna(df['TimeTakenClient']).fillna(df['time_elapsed_s'])
    
    # Calcular Throughput (MB/s)
    df['throughput_mb_s'] = df['file_size_bytes'] / (1024**2) / df['time_s']
    df.replace([np.inf, -np.inf], np.nan, inplace=True) # Reemplazar infinitos por NaN

    print(f"Se procesaron {len(df)} registros de experimentos.")

    # --- Análisis Estadístico ---
    # Agrupar por parámetros de experimento y calcular media y desviación estándar
    stats_df = df.groupby(['mechanism', 'file_size', 'buffer_size_kb', 'sync_mode']).agg(
        mean_throughput_mb_s=('throughput_mb_s', 'mean'),
        std_throughput_mb_s=('throughput_mb_s', 'std'),
        mean_time_s=('time_s', 'mean'),
        std_time_s=('time_s', 'std'),
        mean_cpu_percent=('cpu_percent', 'mean'),
        mean_user_time_s=('time_user_s', 'mean'),
        mean_system_time_s=('time_system_s', 'mean'),
        count=('run', 'count')
    ).reset_index()

    # Calcular intervalo de confianza del 95% para el throughput
    stats_df['ci95_throughput'] = 1.96 * stats_df['std_throughput_mb_s'] / np.sqrt(stats_df['count'])
    
    # Guardar el resumen estadístico
    stats_df.to_csv(SUMMARY_CSV_PATH, index=False)
    print(f"Resumen estadístico guardado en: {SUMMARY_CSV_PATH}")

    # --- Generación de Gráficos ---
    print("Generando gráficos...")
    sns.set_theme(style="whitegrid")

    # 1. Boxplot de Throughput por Mecanismo
    plt.figure(figsize=(15, 8))
    g = sns.boxplot(data=df, x='mechanism', y='throughput_mb_s', hue='file_size',
                    order=['buffered', 'direct', 'sendfile', 'unix_socket', 'tcp_socket'],
                    hue_order=['10M', '100M', '1G'])
    g.set_title('Rendimiento (Throughput) por Mecanismo de E/S y Tamaño de Archivo', fontsize=16)
    g.set_xlabel('Mecanismo', fontsize=12)
    g.set_ylabel('Rendimiento (MB/s)', fontsize=12)
    g.set_yscale('log')
    g.legend(title='Tamaño Archivo')
    plt.xticks(rotation=15)
    plt.tight_layout()
    plt.savefig(os.path.join(CHARTS_DIR, 'throughput_by_mechanism.png'))

    # 2. Gráfico de Tiempo de CPU (User vs System)
    # Seleccionamos un caso representativo: archivo 100M, buffer 64KB
    cpu_df = df[(df['file_size'] == '100M') & (df['buffer_size_kb'] == 64)]
    cpu_stats = cpu_df.groupby('mechanism')[['time_user_s', 'time_system_s']].mean().reset_index()
    cpu_stats_melted = cpu_stats.melt(id_vars='mechanism', var_name='cpu_type', value_name='time_s')
    
    plt.figure(figsize=(12, 7))
    g = sns.barplot(data=cpu_stats_melted, x='mechanism', y='time_s', hue='cpu_type',
                    order=['buffered', 'direct', 'sendfile', 'unix_socket', 'tcp_socket'])
    g.set_title('Tiempo de CPU (User vs System) para Archivo de 100M y Buffer de 64KB', fontsize=16)
    g.set_xlabel('Mecanismo', fontsize=12)
    g.set_ylabel('Tiempo Promedio (s)', fontsize=12)
    plt.xticks(rotation=15)
    plt.tight_layout()
    plt.savefig(os.path.join(CHARTS_DIR, 'cpu_time_comparison.png'))

    # 3. Gráfico de Llamadas al Sistema
    # Contar llamadas al sistema para el mismo caso representativo
    syscall_cols = [c for c in df.columns if 'syscall_' in c]
    syscall_df = df[(df['file_size'] == '100M') & (df['buffer_size_kb'] == 64)]
    syscall_stats = syscall_df.groupby('mechanism')[syscall_cols].sum().reset_index()
    
    # Seleccionar solo las llamadas más relevantes
    relevant_syscalls = ['syscall_read', 'syscall_write', 'syscall_sendfile', 'syscall_sendto', 'syscall_recvfrom']
    relevant_cols = [c for c in syscall_stats.columns if c in relevant_syscalls or c == 'mechanism']
    syscall_stats_melted = syscall_stats[relevant_cols].melt(id_vars='mechanism', var_name='syscall', value_name='count')
    syscall_stats_melted = syscall_stats_melted[syscall_stats_melted['count'] > 0] # Filtrar las que no se llamaron
    
    plt.figure(figsize=(14, 8))
    g = sns.barplot(data=syscall_stats_melted, x='mechanism', y='count', hue='syscall',
                    order=['buffered', 'direct', 'sendfile', 'unix_socket', 'tcp_socket'])
    g.set_title('Total de Llamadas al Sistema (Archivo 100M, Buffer 64KB)', fontsize=16)
    g.set_xlabel('Mecanismo', fontsize=12)
    g.set_ylabel('Número Total de Llamadas (escala log)', fontsize=12)
    g.set_yscale('log')
    plt.xticks(rotation=15)
    plt.tight_layout()
    plt.savefig(os.path.join(CHARTS_DIR, 'syscall_comparison.png'))

    print("Gráficos generados y guardados en:", CHARTS_DIR)
    print("\nAnálisis completado exitosamente.")

if __name__ == '__main__':
    main() 