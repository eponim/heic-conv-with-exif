#!/bin/bash
# этот скрипт обрабатывает файлы из резервной копии GooglePhoto
# и пытается восстановить отсутствующие данные exif в самом файле
# из прилагаемого к нему файла json


# вспомогательная функция, возвращает номер позиции С КОНЦА искомой подстроки в исходной строке
#   $1 - исходная строка
#   $2 - искомая подстрока
strindex() {
  x="${1##*"$2"}"
  [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"
}


creator_work_email="eponim@mail.ru"
creator_work_url="https://www.postogram.org"
magic_quality_persent=87

path="$1"
path_length="${#path}"
dest_path="$2"
cnt_dir=0
cnt_files=0
loop_folder_recurse() {
    for i in "$1"/*;do
        if [ -d "$i" ];then
            echo "dir:" "${i:path_length}"
            if ! [ -d "$dest_path${i:path_length}" ];then
               echo "$dest_path${i:path_length}"
               mkdir "$dest_path${i:path_length}"
            fi
            cnt_dir=$((cnt_dir+1))
            loop_folder_recurse "$i"
        elif [ -f "$i" ] && ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] \
                           || [ "${i##*.}" = "jpg" ] || [ "${i##*.}" = "JPG" ] \
                           || [ "${i##*.}" = "mov" ] || [ "${i##*.}" = "MOV" ] \
                           || [ "${i##*.}" = "mp4" ] || [ "${i##*.}" = "MP4" ] );then
           # проверим, есть ли JSON файл к текущему файлу
           json_file_name="${i}.json"
           if [ -f "$json_file_name" ];then
              echo "$json_file_name"
           else
              # проверяем имя файла на номер дубликата в скобках перед расширением , потому что (например):
              # IMG_1173(1).HEIC -> IMG_1173.HEIC(1).json !!!
              b1_pos=$( strindex "$i" "(" )
              b2_pos=$( strindex "$i" ")" )
              json_file_name="${i:0:${#i}-b1_pos-1}"."${i##*.}""${i:${#i}-b1_pos-1:b1_pos-b2_pos+1}".json
              if [ -f "$json_file_name" ];then
                 echo "$json_file_name"
              else
                 json_file_name=""
                 echo "$i" - JSON file not found!
              fi
           fi

           # HEIC конвертируем в JPG и копируем, остальные просто копируем
           if ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] );then
              # конвертируем HEIC в JPG
              jpg_file_name="$dest_path${i:path_length}"
              jpg_file_name="${jpg_file_name::-4}jpg"
              if ! [ -f "$jpg_file_name" ];then
                 magick "$i" -quality "$magic_quality_persent" "$jpg_file_name"
                 exiftool -DateTimeOriginal "$jpg_file_name"
                 echo "$jpg_file_name"
              fi
           else 
              if ! [ -f "$dest_path${i:path_length}" ];then
                 # cp "$i" "$dest_path${i:path_length}"
                 echo "$i" "$dest_path${i:path_length}"
              fi
           fi
           cnt_files=$((cnt_files+1))
        fi
    done
}

#jq '.photoTakenTime .timestamp' "/mnt/raid1/_public/GooglePhoto/test/IMG_1908.JPG.json"
#exiftool -DateTimeOriginal="$(date -d @1492627832 +%Y:%m:%d\ %T)" "/mnt/raid1/_public/GooglePhoto/test/IMG_1908.JPG"

#echo "Base path: $path"
loop_folder_recurse "$path"
echo "Proseed: dir=$cnt_dir, files=$cnt_files"

a="IMG_1173(1).HEIC"
b=")"
echo -e "\n$a"
b1_pos=$( strindex "$a" "(" )
b2_pos=$( strindex "$a" ")" )
echo -e "${a:0:${#a}-b1_pos-1}"."${a##*.}""${a:${#a}-b1_pos-1:b1_pos-b2_pos+1}".json
