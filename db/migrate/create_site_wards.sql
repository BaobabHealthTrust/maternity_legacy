INSERT INTO global_property (property, property_value, description) VALUES ("statistics.show_encounter_types", "REGISTRATION,OBSERVATIONS,DIAGNOSIS,UPDATE OUTCOME,REFER PATIENT OUT?", "Maternity Encounter Types") ON DUPLICATE KEY UPDATE property = "statistics.show_encounter_types";

INSERT INTO global_property (property, property_value, description) VALUES ("facility.login_wards", "Ante-Natal Ward,Labour Ward,Post-Natal Ward,Gynaecology Ward,Post-Natal Ward (Low Risk),Post-Natal Ward (High Risk),Theater", "") ON DUPLICATE KEY UPDATE property = "facility.login_wards";

INSERT INTO location (name, creator, date_created, retired) VALUES ("Ante-Natal Ward", 1, now(), 0), ("Bwaila Maternity Unit", 1, now(), 0), ("Labour Ward", 1, now(), 0), ("Post-Natal Ward", 1, now(), 0), ("Gynaecology Ward", 1, now(), 0), ("Post-Natal Ward (Low Risk)", 1, now(), 0), ("Post-Natal Ward (High Risk)", 1, now(), 0), ("Kamuzu Central Hospital", 1, now(), 0), ("Theater", 1, now(), 0); 
