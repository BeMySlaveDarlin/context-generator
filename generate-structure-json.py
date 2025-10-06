#!/usr/bin/env python3

import os
import sys
import json
from pathlib import Path

def should_exclude(path, exclude_dirs):
    """Проверка на исключаемые директории"""
    parts = Path(path).parts
    for part in parts:
        if part in exclude_dirs:
            return True
    return False

def build_tree_from_files(root_dir, files, extensions):
    """Построение дерева из списка файлов"""
    tree = {}
    stats = {'directories': 0, 'files': 0, 'targetFiles': 0}
    
    for file_path in files:
        # Относительный путь
        rel_path = os.path.relpath(file_path, root_dir)
        parts = rel_path.split(os.sep)
        
        # Проходим по дереву
        current = tree
        for i, part in enumerate(parts[:-1]):
            if part not in current:
                current[part] = {}
            current = current[part]
        
        # Добавляем файл
        filename = parts[-1]
        current[filename] = file_path
    
    # Конвертируем дерево в нужный формат
    def dict_to_tree(node_dict, relative_path=''):
        result = []
        
        for name, value in sorted(node_dict.items()):
            item_relative = os.path.join(relative_path, name) if relative_path else name
            
            if isinstance(value, dict):
                # Директория
                stats['directories'] += 1
                children = dict_to_tree(value, item_relative)
                result.append({
                    'name': name,
                    'type': 'directory',
                    'path': item_relative,
                    'absolutePath': os.path.join(root_dir, item_relative),
                    'children': children
                })
            else:
                # Файл
                stats['files'] += 1
                
                ext = name.split('.')[-1] if '.' in name else ''
                ext_list = [e.strip() for e in extensions.split(',')]
                
                if ext in ext_list:
                    stats['targetFiles'] += 1
                    
                    node = {
                        'name': name,
                        'type': 'file',
                        'path': item_relative,
                        'absolutePath': value
                    }
                    
                    # Для PHP добавляем class
                    if ext == 'php':
                        class_path = item_relative.replace('.php', '').replace(os.sep, '\\')
                        node['class'] = class_path
                    
                    result.append(node)
        
        return result
    
    tree_result = dict_to_tree(tree)
    return tree_result, stats

def find_files(root_dir, extensions, exclude_dirs):
    """Поиск файлов аналогично collect-php.sh"""
    files = []
    ext_list = [e.strip() for e in extensions.split(',')]
    
    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=True):
        # Исключаем директории на месте
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        
        for filename in sorted(filenames):
            ext = filename.split('.')[-1] if '.' in filename else ''
            if ext in ext_list:
                full_path = os.path.join(dirpath, filename)
                files.append(full_path)
    
    return sorted(files)

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 generate-structure-json.py <root_dir> <output_file> [extensions] [exclude_dirs]")
        print("Example: python3 generate-structure-json.py /src output.json 'php' 'vendor,node_modules,cache'")
        sys.exit(1)
    
    root_dir = sys.argv[1]
    output_file = sys.argv[2]
    extensions = sys.argv[3] if len(sys.argv) > 3 else 'php'
    exclude_str = sys.argv[4] if len(sys.argv) > 4 else 'vendor,node_modules,.git,cache,storage,var,runtime'
    
    exclude_dirs = set(exclude_str.replace('|', ',').split(','))
    
    if not os.path.isdir(root_dir):
        print(f"Error: Directory not found: {root_dir}")
        sys.exit(1)
    
    # Находим все файлы
    files = find_files(root_dir, extensions, exclude_dirs)
    
    # Строим дерево
    tree, stats = build_tree_from_files(root_dir, files, extensions)
    
    result = {
        'root': root_dir,
        'stats': stats,
        'tree': tree
    }
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"✓ Structure generated: {stats['directories']} dirs, {stats['files']} files ({stats['targetFiles']} target)")

if __name__ == '__main__':
    main()
