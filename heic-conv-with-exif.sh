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



# временные файлы
tmp_dir="/dev/shm/"

date_time_start=$( date +%s )
creator_work_email="eponim@mail.ru"
creator_work_url="https://www.postogram.org"
magic_quality_persent=87

path="$1"
path_length="${#path}"
dest_path="$2"
cnt_dir=0
cnt_files=0

# подпапка в каждой копируемой директории, куда будем записывать файлы без установленной даты съёмки
no_date_path="/.nodate"

loop_folder_recurse() {
    for i in "$1"/*;do
        if [ -d "$i" ];then
            echo "dir:" "${i:path_length}"
            if ! [ -d "$dest_path${i:path_length}" ];then
 #              echo "$dest_path${i:path_length}"
               mkdir "$dest_path${i:path_length}"
               mkdir "$dest_path${i:path_length}$no_date_path"
            fi
            cnt_dir=$((cnt_dir+1))
            loop_folder_recurse "$i"
        elif [ -f "$i" ] && ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] \
                           || [ "${i##*.}" = "jpg" ] || [ "${i##*.}" = "JPG" ] \
                           || [ "${i##*.}" = "mov" ] || [ "${i##*.}" = "MOV" ] \
                           || [ "${i##*.}" = "mp4" ] || [ "${i##*.}" = "MP4" ] );then

           tmp_jpg_file="/dev/shm/tmp-heic-conv-with-exif.${i##*.}"

           # проверим, есть ли JSON файл к текущему файлу
           json_file_name="${i}.json"
           if [ -f "$json_file_name" ];then
#              echo "$json_file_name"
               a=1
           else
              # проверяем имя файла на номер дубликата в скобках перед расширением , потому что (например):
              # IMG_1173(1).HEIC -> IMG_1173.HEIC(1).json !!!
              b1_pos=$( strindex "$i" "(" )
              b2_pos=$( strindex "$i" ")" )
              json_file_name="${i:0:${#i}-b1_pos-1}"."${i##*.}""${i:${#i}-b1_pos-1:b1_pos-b2_pos+1}".json
              if [ -f "$json_file_name" ];then
#                 echo "$json_file_name"
                  a=1
              else
                 json_file_name=""
#                 echo "$i" - JSON file not found...
              fi
           fi

           # заберём из JSON файла дату/время съёмки и GPS координаты
           if [ -f "$json_file_name" ];then
              j_dt=$( jq '.photoTakenTime .timestamp' "$json_file_name" )
              j_lt=$( jq '.geoDataExif .latitude' "$json_file_name" )
              j_lg=$( jq '.geoDataExif .longitude' "$json_file_name" )
              j_al=$( jq '.geoDataExif .altitude' "$json_file_name" )
           fi

           # заменим расширение временного файла для видео-файлов (уже не надо)
#           if ( [ "${i##*.}" = "MOV" ] || [ "${i##*.}" = "mov" ] || [ "${i##*.}" = "MP4" ] || [ "${i##*.}" = "mp4" ] );then
#              tmp_jpg_file="${tmp_jpg_file::-3}${i##*.}"
#              echo "Tmp jpg file: $tmp_jpg_file"
#           fi

           #если у файла нет даты съёмки, то no_date="$no_date_path"
           no_date=""

           # HEIC конвертируем в JPG и копируем в tmp_jpg_file, остальные просто копируем в tmp_jpg_file
           if ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] );then
              tmp_jpg_file="${tmp_jpg_file::-4}jpg"
              magick "$i" -quality "$magic_quality_persent" "$tmp_jpg_file" # конвертируем с заданным качеством
           else
              cp "$i" "$tmp_jpg_file"
           fi

           # извлечём данные из фото и видео
           if ( [ "${i##*.}" = "MOV" ] || [ "${i##*.}" = "mov" ] || [ "${i##*.}" = "MP4" ] || [ "${i##*.}" = "mp4" ] );then
              f_dt=$( exiftool -fast -CreateDate -n "$tmp_jpg_file" )
              f_dt="${f_dt:34}"
#              echo "$f_dt"
              if ( [ ${#f_dt} = 0 ] || [ "$f_dt" = "0000:00:00 00:00:00" ] );then
#                 echo "MediaCreateDate"
                 f_dt=$( exiftool -fast -MediaCreateDate -n "$tmp_jpg_file" )
                 f_dt="${f_dt:34}"
                 if ( [ ${#f_dt} = 0 ] || [ "$f_dt" = "0000:00:00 00:00:00" ] );then
                    f_dt=""
                 fi
              fi
           else
              f_dt=$( exiftool -fast -DateTimeOriginal -n "$tmp_jpg_file" )
           fi
           f_lt=$( exiftool -fast -GPSLatitude -n "$tmp_jpg_file" )
           f_lg=$( exiftool -fast -GPSLongitude -n "$tmp_jpg_file" )
           f_al=$( exiftool -fast -GPSAltitude -n "$tmp_jpg_file" )

           # 1. Проверим, есть ли в фото дата съёмки, если нет - попоробуем взять из JSON
           # 2. Установим дату создания файла равной дате съёмки
#           echo -e "DateTimeOriginal: ${f_dt#*:}, ${#f_dt}, "$( date --date="@${j_dt//\"/}" +"%F %T")
           if ( [ ${#f_dt} = 0 ] );then
              no_date="$no_date_path"
#              echo "Date from JSON: $j_dt ${#j_dt} $( date --date="@${j_dt//\"/}" +"%F %T")"
              if ( [ -n "$j_dt" ] );then
#                 echo "Try set JSON date"
                 date_touch=$( date --date="@${j_dt//\"/}" +"%F %T")
                 exiftool -DateTimeOriginal="$date_touch" "$tmp_jpg_file"
                 touch -mad "$date_touch" "$tmp_jpg_file"
                 no_date=""
              fi
           else
              dt="${f_dt#*: }"
              date1="${dt% *}"
              date2="${date1//:/-}"
              time1="${dt#* }"
              date_touch=$( echo "$date2" "$time1" )
              touch -mad "$date_touch" "$tmp_jpg_file"
           fi

           # проверим, есть ли в фото GPS координаты, если нет - попоробуем взять из JSON
#           echo -e "GPSLatitude:      $f_lt, ${#f_lt}, $j_lt"
#           echo -e "GPSLongitude:     $f_lg, ${#f_lg}, $j_lg"
#           echo -e "GPSAltitude:      $f_al, ${#f_al}, $j_al"
           null=0
           if ( [ -z "$f_lt" ] && [ "$j_lt" != "$null" ] );then
#              echo "Try set JSON coordinate"
              if ( [ "${i##*.}" = "MOV" ] || [ "${i##*.}" = "mov" ] || [ "${i##*.}" = "MP4" ] || [ "${i##*.}" = "mp4" ] );then
#                 echo "MOV"
                 exiftool -overwrite_original -GPSLatitude="$j_lt" -GPSLongitude="$j_lg" -GPSAltitude="$j_al" "$tmp_jpg_file"
              else
                 exiftool -GPSLatitude="$j_lt" -GPSLongitude="$j_lg" -GPSAltitude="$j_al" "$tmp_jpg_file"
              fi
           fi

           # сформируем имя выходного файла
           jpg_file_name="$dest_path${i:path_length}"
           if ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] );then
              jpg_file_name="${jpg_file_name::-4}jpg" # заменим расширение HEIC на JPG
           fi

           # если без даты съёмки, то добавим в путь .nodate
           fn=$( basename "$jpg_file_name" )
           fn_lenth="${#fn}"
           jpg_file_name="${jpg_file_name::-fn_lenth-1}$no_date/$fn"
           cp -v -f --preserve=all "$tmp_jpg_file" "$jpg_file_name"
           echo -e "Скопирован          : $i -> $jpg_file_name\n"

           # очистим временный файл
#           if [ -f "$tmp_jpg_file" ];then
#              rm "$tmp_jpg_file"
#           fi

           cnt_files=$((cnt_files+1))
#           echo -e "\n"
        fi
    done
}

#jq '.photoTakenTime .timestamp' "/mnt/raid1/_public/GooglePhoto/test/IMG_1908.JPG.json"
#exiftool -DateTimeOriginal="$(date -d @1492627832 +%Y:%m:%d\ %T)" "/mnt/raid1/_public/GooglePhoto/test/IMG_1908.JPG"

#echo "Base path: $path"
mkdir "$dest_path$no_date_path"
loop_folder_recurse "$path"
execution_time=$( date +%s )
execution_time=$(( $execution_time-$date_time_start ))

echo "Proseed: dir=$cnt_dir, files=$cnt_files, time="$( date --date="@$execution_time" +"%X" -u )
