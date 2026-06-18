module gtools

import os

pub struct FileHandle {
mut:
	__path    string
	__content string
}

pub fn new_file_handle(file_path ?string, ext ?string) FileHandle {
	final_ext := ext or { '.txt' }
	final_path := file_path or { os.join_path(os.cwd(), 'default' + final_ext) }

	os.write_file(final_path, '')

	return FileHandle{
		__path: final_path
		__content: ''
	}
}

pub fn (fh FileHandle) exists() bool {
	return os.exists(fh.__path)
}

pub fn (mut fh FileHandle) write_file(content ?string) {
	final_content := content or { '' }
	os.write_file(fh.__path, final_content)
	fh.__content = final_content
}

pub fn (fh FileHandle) get_content() string {
	return fh.__content
}

pub fn (mut fh FileHandle) append_file(content ?string) {
	tmp_content := content or { '' }
	final_content := fh.__content + tmp_content
	fh.write_file(final_content)
}

pub fn (mut fh FileHandle) append_at_top(content ?string) {
	tmp_content := content or { '' }
	cache_content := fh.__content
	fh.write_file(tmp_content)
	fh.append_file(cache_content)
}

pub fn (fh FileHandle) get_path() string {
	return fh.__path
}

pub fn (fh FileHandle) read_line(idx int) ?string {
	lines := fh.__content.split_into_lines()

	if idx < 0 || idx >= lines.len {
		return none
	}

	return lines[idx]
}

pub fn (mut fh FileHandle) move_file(path string) {
	os.mv(fh.__path, path) or {
		return
	}

	fh.__path = path
}