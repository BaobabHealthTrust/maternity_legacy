class Person < ActiveRecord::Base
  set_table_name "person"
  set_primary_key "person_id"

  include Openmrs

  cattr_accessor :session_datetime
  attr_accessor :education_level, :religion

  has_one :patient, :foreign_key => :patient_id, :dependent => :destroy
  has_one :birth_report, :foreign_key => :person_id, :dependent => :destroy
  has_many :names, :class_name => 'PersonName', :foreign_key => :person_id, :dependent => :destroy, :conditions => 'person_name.voided = 0', :order => 'person_name.preferred DESC'
  has_many :addresses, :class_name => 'PersonAddress', :foreign_key => :person_id, :dependent => :destroy, :conditions => 'person_address.voided = 0', :order => 'person_address.preferred DESC'
  has_many :person_attributes, :foreign_key => :person_id, :dependent => :destroy #, :conditions => 'person.voided = 0'
  has_many :observations, :class_name => 'Observation', :foreign_key => :person_id, :dependent => :destroy, :conditions => 'obs.voided = 0' do

    def find_by_concept_name(name)
      concept_name = ConceptName.find_by_name(name)
      find(:all, :conditions => ['concept_id = ?', concept_name.concept_id]) rescue []
    end
  end
  #  accepts_nested_attributes_for :names, :addresses, :patient

  
  def name
    "#{self.names.first.given_name} #{self.names.first.family_name}" rescue nil
  end  

  def address
    "#{self.addresses.first.city_village}" rescue nil
  end 

  def age(today = Date.today)
    return nil if self.birthdate.nil?

    # This code which better accounts for leap years
    patient_age = (today.year - self.birthdate.year) + ((today.month - self.birthdate.month) + ((today.day - self.birthdate.day) < 0 ? -1 : 0) < 0 ? -1 : 0)

    # If the birthdate was estimated this year, we round up the age, that way if
    # it is March and the patient says they are 25, they stay 25 (not become 24)
    birth_date=self.birthdate
    estimate=self.birthdate_estimated
    patient_age += (estimate && birth_date.month == 7 && birth_date.day == 1  && 
        today.month < birth_date.month && self.date_created.year == today.year) ? 1 : 0
  end

  def age_in_months(today = Date.today)
    years = (today.year - self.birthdate.year)
    months = (today.month - self.birthdate.month)
    (years * 12) + months
  end
    
  def birthdate_formatted
    if self.birthdate_estimated
      if self.birthdate.day == 1 and self.birthdate.month == 7
        self.birthdate.strftime("??/???/%Y")
      elsif self.birthdate.day == 15 
        self.birthdate.strftime("??/%b/%Y")
      end
    else
      self.birthdate.strftime("%d/%b/%Y")
    end
  end

  def set_birthdate(year = nil, month = nil, day = nil)   
    raise "No year passed for estimated birthdate" if year.nil?

    # Handle months by name or number (split this out to a date method)    
    month_i = (month || 0).to_i
    month_i = Date::MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
    month_i = Date::ABBR_MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
    
    if month_i == 0 || month == "Unknown"
      self.birthdate = Date.new(year.to_i,7,1)
      self.birthdate_estimated = 1
    elsif day.blank? || day == "Unknown" || day == 0
      self.birthdate = Date.new(year.to_i,month_i,15)
      self.birthdate_estimated = 1
    else
      self.birthdate = Date.new(year.to_i,month_i,day.to_i)
      self.birthdate_estimated = 0
    end
  end

  def set_birthdate_by_age(age, today = Date.today)
    self.birthdate = Date.new(today.year - age.to_i, 7, 1)
    self.birthdate_estimated = 1
  end

  def demographics


    if self.birthdate_estimated
      birth_day = "Unknown"
      if self.birthdate.month == 7 and self.birthdate.day == 1
        birth_month = "Unknown"
      else
        birth_month = self.birthdate.month
      end
    else
      birth_month = self.birthdate.month
      birth_day = self.birthdate.day
    end

    demographics = {"person" => {
        "date_changed" => self.date_changed.to_s,
        "gender" => self.gender,
        "birth_year" => self.birthdate.year,
        "birth_month" => birth_month,
        "birth_day" => birth_day,
        "names" => {
          "given_name" => self.names[0].given_name,
          "family_name" => self.names[0].family_name,
          "family_name2" => ""
        },
        "addresses" => {
          "county_district" => "",
          "city_village" => self.addresses[0].city_village
        },
      }}
 
    if not self.patient.patient_identifiers.blank? 
      demographics["person"]["patient"] = {"identifiers" => {}}
      self.patient.patient_identifiers.each{|identifier|
        demographics["person"]["patient"]["identifiers"][identifier.type.name] = identifier.identifier
      }
    end

    return demographics
  end

  def self.search_by_identifier(identifier)
    PatientIdentifier.find_all_by_identifier(identifier).map{|id| id.patient.person} unless identifier.blank?
  end

  def self.search(params)
    people = Person.search_by_identifier(params[:identifier])

    return people.first.id unless people.blank? || people.size > 1
    people = Person.find(:all, :include => [{:names => [:person_name_code]}, :patient], :conditions => [
        "gender = ? AND \
     person.voided = 0 AND \
     (patient.voided = 0 OR patient.voided IS NULL) AND \
     (person_name.given_name LIKE ? OR person_name_code.given_name_code LIKE ?) AND \
     (person_name.family_name LIKE ? OR person_name_code.family_name_code LIKE ?)",
        params[:gender],
        params[:given_name],
        (params[:given_name] || '').soundex,
        params[:family_name],
        (params[:family_name] || '').soundex
      ]) if people.blank?

    return people
    
    # temp removed
    # AND (person_name.family_name2 LIKE ? OR person_name_code.family_name2_code LIKE ? OR person_name.family_name2 IS NULL )"    
    #  params[:family_name2],
    #  (params[:family_name2] || '').soundex,




    # CODE below is TODO, untested and NOT IN USE
    #    people = []
    #    people = PatientIdentifier.find_all_by_identifier(params[:identifier]).map{|id| id.patient.person} unless params[:identifier].blank?
    #    if people.size == 1
    #      return people
    #    elsif people.size >2
    #      filtered_by_family_name_and_gender = []
    #      filtered_by_family_name = []
    #      filtered_by_gender = []
    #      people.each{|person|
    #        gender_match = person.gender == params[:gender] unless params[:gender].blank?
    #        filtered_by_gender.push person if gender_match
    #        family_name_match = person.first.names.collect{|name|name.family_name.soundex}.include? params[:family_name].soundex
    #        filtered_by_family_name.push person if gender_match?
    #        filtered_by_family_name_and_gender.push person if family_name_match? and gender_match?
    #      }
    #      return filtered_by_family_name_and_gender unless filtered_by_family_name_and_gender.empty?
    #      return filtered_by_family_name unless filtered_by_family_name.empty?
    #      return filtered_by_gender unless filtered_by_gender.empty?
    #      return people
    #    elseservers = CoreService.get_global_property_value("remote_servers.parent")

      server_address_and_port = servers.to_s.split(':')

      server_address = server_address_and_port.first
      server_port = server_address_and_port.second

      login = CoreService.get_global_property_value("remote_bart.username").split(/,/) rescue ""
      password = CoreService.get_global_property_value("remote_bart.password").split(/,/) rescue ""
      location = CoreService.get_global_property_value("remote_bart.location").split(/,/) rescue nil
      machine = CoreService.get_global_property_value("remote_machine.account_name").split(/,/) rescue ''

      uri = "http://#{server_address}:#{server_port}/people/remote_demographics"

      p = JSON.parse(RestClient.post(uri, known_demographics)).first # rescue nil

    #    return people if people.size == 1
    #    people = Person.find(:all, :include => [{:names => [:person_name_code]}, :patient], :conditions => [
    #    "gender = ? AND \
    #     person.voided = 0 AND \
    #     (patient.voided = 0 OR patient.voided IS NULL) AND \
    #     (person_name.given_name LIKE ? OR person_name_code.given_name_code LIKE ?) AND \
    #     (person_name.family_name LIKE ? OR person_name_code.family_name_code LIKE ?)",
    #    params[:gender],
    #    params[:given_name],
    #    (params[:given_name] || '').soundex,
    #    params[:family_name],
    #    (params[:family_name] || '').soundex
    #    ]) if people.blank?
    #
    # temp removed
    # AND (person_name.family_name2 LIKE ? OR person_name_code.family_name2_code LIKE ? OR person_name.family_name2 IS NULL )"    
    #  params[:family_name2],
    #  (params[:family_name2] || '').soundex,

  end

  def self.find_by_demographics(person_demographics)
    national_id = person_demographics["person"]["patient"]["identifiers"]["National id"] rescue nil
    results = Person.search_by_identifier(national_id) unless national_id.nil?
    return results unless results.blank?

    gender = person_demographics["person"]["gender"] rescue nil
    given_name = person_demographics["person"]["names"]["given_name"] rescue nil
    family_name = person_demographics["person"]["names"]["family_name"] rescue nil

    search_params = {:gender => gender, :given_name => given_name, :family_name => family_name }

    results = Person.search(search_params)

  end

  def self.create_from_form_old(params)
    
    #return rescue text if remote timed out or creation of patient on remote failed
    if params.to_s == 'timeout' || params.to_s == 'creationfailed'
      return params.to_s
    end
    
    if params.has_key?('person')
      params = params['person']
    end

    address_params = params["addresses"]
    names_params = params["names"]
    patient_params = params["patient"]
    person_attribute_params = params["attributes"]

    params_to_process = params.reject{|key,value| key.match(/addresses|patient|names|attributes/) }
    birthday_params = params_to_process.reject{|key,value| key.match(/gender/) }
    person_params = params_to_process.reject{|key,value|
      key.match(/birth_|age_estimate|race|occupation|citizenship|home_phone_number|cell_phone_number/) }

    # raise person_params.to_yaml

    if params.has_key?('person')
      person = Person.create(person_params[:person])
    else
      person = Person.create(person_params)
    end   
    
    if birthday_params["birth_year"] == "Unknown"
      person.set_birthdate_by_age(birthday_params["age_estimate"])
    else
      person.set_birthdate(birthday_params["birth_year"], birthday_params["birth_month"], birthday_params["birth_day"])
    end
    person.birthdate_estimated = 1 if params["birthdate_estimated"] == 'true'
    person.save
    person.names.create(names_params)
    person.addresses.create(address_params)

    # add person attributes
    person_attribute_params.each do |attribute_type_name, attribute|
      attribute_type = PersonAttributeType.find_by_name(attribute_type_name.humanize.titleize) || 
        PersonAttributeType.find_by_name("Unknown id")

      person.person_attributes.create("value" => attribute, "person_attribute_type_id" => 
          attribute_type.person_attribute_type_id) unless attribute.blank? rescue nil

    end if person_attribute_params

    # TODO handle the birthplace attribute
 
    if (!patient_params.nil?)
      patient = person.create_patient

      patient_params["identifiers"].each{|identifier_type_name, identifier|
        identifier_type = PatientIdentifierType.find_by_name(identifier_type_name.gsub('_', ' ')) || PatientIdentifierType.find_by_name("Unknown id")
        next if identifier.empty?
        patient.patient_identifiers.create("identifier" => identifier, "identifier_type" => identifier_type.patient_identifier_type_id)
      } if patient_params["identifiers"]


      
      # This might actually be a national id, but currently we wouldn't know
      #patient.patient_identifiers.create("identifier" => patient_params["identifier"], "identifier_type" => PatientIdentifierType.find_by_name("Unknown id")) unless params["identifier"].blank?
    end
    return person
  end

  def self.create_from_form(params)
    #return rescue text if remote timed out or creation of patient on remote failed
    if params.to_s == 'timeout' || params.to_s == 'creationfailed'
      return params.to_s
    end

     params = params['person']? params['person'] : params
	    
    	address_params = params["addresses"]
		names_params = params["names"]
		patient_params = params["patient"]
		
		params_to_process = params.reject{|key,value| key.match(/addresses|patient|names|relation|cell_phone_number|home_phone_number|office_phone_number|agrees_to_be_visited_for_TB_therapy|agrees_phone_text_for_TB_therapy/) }
		
		birthday_params = params_to_process.reject{|key,value| key.match(/gender/) }
		person_params = params_to_process.reject{|key,value| key.match(/birth_|age_estimate|occupation|identifiers|citizenship|race/) }

		if person_params["gender"].to_s == "Female"
        	person_params["gender"] = 'F'
		elsif person_params["gender"].to_s == "Male"
        	person_params["gender"] = 'M'
		end

     	person_params["attributes"].delete("occupation") if person_params["attributes"]
     	person_params["attributes"].delete("cell_phone_number") if person_params["attributes"]
		person_params["attributes"].delete("place_of_birth") if person_params["attributes"]
		person_params["attributes"].delete("landmark_or_plot_number") if person_params["attributes"]

      	person = Person.create(person_params)

		unless birthday_params.empty?
		  if birthday_params["birth_year"] == "Unknown"
        self.set_birthdate_by_age(person, birthday_params["age_estimate"], person.session_datetime || Date.today)
		  else
        self.set_birthdate(person, birthday_params["birth_year"], birthday_params["birth_month"], birthday_params["birth_day"])
		  end
		end

		person.save  

		person.names.create(names_params)
		person.addresses.create(address_params) unless address_params.empty? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Place Of Birth").person_attribute_type_id,
		  :value => params["place_of_birth"]) unless params["occupation"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Landmark Or Plot Number").person_attribute_type_id,
		  :value => params["landmark_or_plot_number"]) unless params["landmark_or_plot_number"].blank? rescue nil


		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Occupation").person_attribute_type_id,
		  :value => params["occupation"]) unless params["occupation"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Cell Phone Number").person_attribute_type_id,
		  :value => params["cell_phone_number"]) unless params["cell_phone_number"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Office Phone Number").person_attribute_type_id,
		  :value => params["office_phone_number"]) unless params["office_phone_number"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Home Phone Number").person_attribute_type_id,
		  :value => params["home_phone_number"]) unless params["home_phone_number"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Citizenship").person_attribute_type_id,
		  :value => params["citizenship"]) unless params["citizenship"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Race").person_attribute_type_id,
		  :value => params["race"]) unless params["race"].blank? rescue nil

    # TODO handle the birthplace attribute

		if (!patient_params.nil?)
		  patient = person.create_patient

		  patient_params["identifiers"].each{|identifier_type_name, identifier|
        next if identifier.blank?
        identifier_type = PatientIdentifierType.find_by_name(identifier_type_name) || PatientIdentifierType.find_by_name("Unknown id")
        patient.patient_identifiers.create("identifier" => identifier, "identifier_type" => identifier_type.patient_identifier_type_id)
		  } if patient_params["identifiers"]

		  # This might actually be a national id, but currently we wouldn't know
		  #patient.patient_identifiers.create("identifier" => patient_params["identifier"], "identifier_type" => PatientIdentifierType.find_by_name("Unknown id")) unless params["identifier"].blank?
		end

		return person
  end

  def self.set_birthdate_by_age(person, age, today = Date.today)
    person.birthdate = Date.new(today.year - age.to_i, 7, 1)
    person.birthdate_estimated = 1
  end

  def self.set_birthdate(person, year = nil, month = nil, day = nil)
    raise "No year passed for estimated birthdate" if year.nil?

    # Handle months by name or number (split this out to a date method)
    month_i = (month || 0).to_i
    month_i = Date::MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
    month_i = Date::ABBR_MONTHNAMES.index(month) if month_i == 0 || month_i.blank?

    if month_i == 0 || month == "Unknown"
      person.birthdate = Date.new(year.to_i,7,1)
      person.birthdate_estimated = 1
    elsif day.blank? || day == "Unknown" || day == 0
      person.birthdate = Date.new(year.to_i,month_i,15)
      person.birthdate_estimated = 1
    else
      person.birthdate = Date.new(year.to_i,month_i,day.to_i)
      person.birthdate_estimated = 0
    end
  end

  def self.find_remote_by_identifier(identifier)
    known_demographics = {:person => {:patient => { :identifiers => {"National id" => identifier }}}}
    result = Person.find_remote(known_demographics)
  end

  # use the autossh tunnels setup in environment.rb to query the demographics servers
  # then pull down the demographics
  def self.find_remote(known_demographics)
     create_from_remote = CoreService.get_global_property_value("create.from.remote")
	  if create_from_remote
	  servers = CoreService.get_global_property_value("remote_servers.parent")
      server_address_and_port = servers.to_s.split(':')

      server_address = server_address_and_port.first
      server_port = server_address_and_port.second

      login = CoreService.get_global_property_value("remote_bart.username").split(/,/) rescue ""
      password = CoreService.get_global_property_value("remote_bart.password").split(/,/) rescue ""
      location = CoreService.get_global_property_value("remote_bart.location").split(/,/) rescue nil
      machine = CoreService.get_global_property_value("remote_machine.account_name").split(/,/) rescue ''

      uri = "http://#{server_address}:#{server_port}/people/remote_demographics"
      
      p = JSON.parse(RestClient.post(uri, known_demographics)).first # rescue nil
      return nil if p.blank?

      results = p.second if p.second and p.first.match /person/

      results["occupation"] = results["attributes"]["occupation"]
      results["cell_phone_number"] = results["attributes"]["cell_phone_number"]
      results["home_phone_number"] =  results["attributes"]["home_phone_number"]
      results["office_phone_number"] = results["attributes"]["office_phone_number"]
      results["attributes"].delete("occupation")
      results["attributes"].delete("cell_phone_number")
      results["attributes"].delete("home_phone_number")
      results["attributes"].delete("office_phone_number")

      return [self.create_from_form(results)]
    end
   end
  
  def formatted_gender

    if self.gender == "F" then "Female"
    elsif self.gender == "M" then "Male"
    else "Unknown"
    end
    
  end

  def self.create_remote(received_params)
    new_params = received_params[:person]
    known_demographics = Hash.new()
    new_params['gender'] == 'F' ? new_params['gender'] = "Female" : new_params['gender'] = "Male"

    known_demographics = {
      "occupation"=>"#{new_params[:attributes][:occupation]}",
      "education_level"=>"#{new_params[:attributes][:education_level]}",
      "religion"=>"#{new_params[:attributes][:religion]}",
      "patient_year"=>"#{new_params[:birth_year]}",
      "patient"=>{
        "gender"=>"#{new_params[:gender]}",
        "birthplace"=>"#{new_params[:addresses][:address2]}",
        "creator" => 1,
        "changed_by" => 1
      },
      "p_address"=>{
        "identifier"=>"#{new_params[:addresses][:state_province]}"},
      "home_phone"=>{
        "identifier"=>"#{new_params[:attributes][:home_phone_number]}"},
      "cell_phone"=>{
        "identifier"=>"#{new_params[:attributes][:cell_phone_number]}"},
      "office_phone"=>{
        "identifier"=>"#{new_params[:attributes][:office_phone_number]}"},
      "patient_id"=>"",
      "patient_day"=>"#{new_params[:birth_day]}",
      "patientaddress"=>{"city_village"=>"#{new_params[:addresses][:city_village]}"},
      "patient_name"=>{
        "family_name"=>"#{new_params[:names][:family_name]}",
        "given_name"=>"#{new_params[:names][:given_name]}", "creator" => 1
      },
      "patient_month"=>"#{new_params[:birth_month]}",
      "patient_age"=>{
        "age_estimate"=>"#{new_params[:age_estimate]}"
      },
      "age"=>{
        "identifier"=>""
      },
      "current_ta"=>{
        "identifier"=>"#{new_params[:addresses][:county_district]}"}
    }
       
   demographic_server = CoreService.get_global_property_value("remote_servers.parent") 
	begin
   output = RestClient.post("http://#{demographic_server}/people/create_remote", known_demographics)
      rescue Timeout::Error 
        return 'timeout'
      rescue
        return 'creationfailed'
      end

      output if output and output.match(/person/)

   output ? JSON.parse(output) : nil
  end

  def phone_numbers
    phone_numbers = {}
    ["Cell Phone Number","Home Phone Number","Office Phone Number"].each{|attribute_type_name|
      number = PersonAttribute.find(:first,:conditions => ["voided = 0 AND person_attribute_type_id = ? AND person_id = ?", PersonAttributeType.find_by_name("#{attribute_type_name}").id, self.id]).value rescue ""
      phone_numbers[attribute_type_name] = number 
    }
    phone_numbers
    phone_numbers.delete_if {|key, value| value == "" }
  end

  def occupation
    occupation = PersonAttribute.find(:first,:conditions => ["voided = 0 AND person_attribute_type_id = ? AND person_id = ?", PersonAttributeType.find_by_name('Occupation').id, self.id]).value rescue 'Uknown'
  end

  def self.update_demographics(params)
    person = Person.find(params['person_id'])
    
    if params.has_key?('person')
      params = params['person']
    end
    
    address_params = params["addresses"]
    names_params = params["names"]
    patient_params = params["patient"]
    person_attribute_params = params["attributes"]

    params_to_process = params.reject{|key,value| key.match(/addresses|patient|names|attributes/) }
    birthday_params = params_to_process.reject{|key,value| key.match(/gender/) }

    person_params = params_to_process.reject{|key,value| key.match(/birth_|age_estimate/) }
   
    if !birthday_params.empty?
      
      if birthday_params["birth_year"] == "Unknown"
        person.set_birthdate_by_age(birthday_params["age_estimate"])
      else
        person.set_birthdate(birthday_params["birth_year"], birthday_params["birth_month"], birthday_params["birth_day"])
      end
      
      person.birthdate_estimated = 1 if params["birthdate_estimated"] == 'true'
      person.save
    end
    
    person.update_attributes(person_params) if !person_params.empty?
    person.names.first.update_attributes(names_params) if names_params
    person.addresses.first.update_attributes(address_params) if address_params

    #update or add new person attribute
    person_attribute_params.each{|attribute_type_name, attribute|
      attribute_type = PersonAttributeType.find_by_name(attribute_type_name.humanize.titleize) || PersonAttributeType.find_by_name("Unknown id")
      #find if attribute already exists
      exists_person_attribute = PersonAttribute.find(:first, :conditions => ["person_id = ? AND person_attribute_type_id = ?", person.id, attribute_type.person_attribute_type_id]) rescue nil
      if exists_person_attribute
        exists_person_attribute.update_attributes({'value' => attribute})
      else
        person.person_attributes.create("value" => attribute, "person_attribute_type_id" => attribute_type.person_attribute_type_id)
      end
    } if person_attribute_params

  end
  
  # Person's short name to fit on small labels
  def short_name
    "#{self.names.first.given_name.first}. #{self.names.first.family_name}" rescue nil
  end

  def current_residence
    #current_residence = PersonAttribute.find(:first,:conditions => ["voided = 0 AND person_attribute_type_id = ? AND person_id = ?",
    #    PersonAttributeType.find_by_name('Current Place Of Residence').id, self.id]).value rescue 'Unknown'

    self.addresses.last.city_village rescue 'Unknown'
  end

  def sex
    if self.gender == "M"
      return "Male"
    elsif self.gender == "F"
      return "Female"
    else
      return nil
    end
  end
end
