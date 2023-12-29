/* Before running the file, please make sure to insert the right-hand side of the %let statement
the path where the folder that contains both the 'tmdb_5000_movies.csv' and 'tmdb_5000_credits.csv'
is located. */
%let folder_path=;

/* Term Project Description
Task: Write a SAS macro that accepts a genre and reports the relative frequency of movies for which a 
producer, executive producer or director of a given movie also appeared as a cast member in that movie (as 
listed in the credits). Your macro should also allow the user to specify a list of genres to be compared.

Instructions: Before running the file, change the %let folder_path= statement to specify the folder
where the 'tmdb_5000_movies.csv' and 'tmdb_5000_credits.csv' datasets are saved. This file has two sections.
The first section preprocesses the two provided datasets and prepares the data for the macro to work on. The
second section defines the macro to complete the assigned task. Running the whole file will execute both sections.

Finally, invoke the macro as in these examples:

%frequency_calculator('Action' 'Adventure');

%frequency_calculator('Action');
*/

*--------------- SECTION 1: PREPROCESSING THE DATA;

/* read in movies data */
data movies;
	infile "&folder_path.\tmdb_5000_movies.csv"
		firstobs=2
		lrecl=100000
		dsd;
	informat budget best32.;
	informat genres $160.;
    informat homepage $82.;
    informat id best32.;
    input budget genres $ homepage $ id;
	drop budget homepage;
run;

/* read in credits data */
data credits;
	infile "&folder_path.\tmdb_5000_credits.csv"
		firstobs=2
		obs=20
		lrecl=100000
		dsd;
	informat movie_id best32.;
	informat title $43.;
	informat cast $28775.;
	informat crew $30000.;
	input movie_id title $ cast $ crew $;
run;

/* join the above two datasets to only get necessary columns */
proc sql noprint;
create table joined_data as select genres, id, credits.title, cast, crew
	from movies 
	join credits
	on movies.id = credits.movie_id;

select * from joined_data;
quit;

/* extract cast names */
data cast;
	set joined_data;

	ed_curly_cast = count(cast, '}');
	do i=1 to ed_curly_cast;
		cast_info = scan(cast, i, '}');
		name_start = find(cast_info, '"name":') + 8;
		name_end = find(cast_info, ':', name_start);
		cast_name = scan(substr(cast_info, name_start, name_end - name_start), 1, '":');
		output;
	end; 

	keep title genres cast_name;
run;

/* extract crew names whose job is either producer, executive producer, or director */
data crew;
    set joined_data;

    ed_curly = count(crew, '}');
    do i = 1 to ed_curly;
        crew_info = scan(crew, i, '}');
        job_start = find(crew_info, '"job":') + 7;
        job_end = find(crew_info, '"', job_start);
        crew_job = scan(substr(crew_info, job_start, job_end - job_start), 1, ',');
        crew_job = strip(translate(crew_job, ' ', '"'));

        /* keep crew members who are either a producer, executive producer, or director */
        if crew_job in ('Producer', 'Executive Producer', 'Director') then do;
            name_start = find(crew_info, '"name":') + 8;
            name_end = find(crew_info, '"', name_Start);
            crew_name = scan(substr(crew_info, name_start, name_end - name_start), 1, ',');
            crew_name = strip(translate(crew_name, ' ', '"'));
            output;
        end;
    end;

    keep title genres crew_name;
run;

/* some crew member hold more than one job -> create duplicates */
proc sort data=crew out=crew_clean nodupkey;
    by crew_name; *sort the dataset to remove duplicates;
run;

/* combine the cast and the crew name extractions */
proc sql;
    create table cast_crew as
    select a.genres, a.title, a.cast_name, b.crew_name
    from cast as a
    inner join crew_clean as b
    on a.title = b.title and a.genres = b.genres;
quit;

/* expand genre list 
   in cast_crew, each observation has a genre list. for example, ['Action', 'Adventure'].
   this data step will expand this observation into 2 rows for 'Action' and 'Adventure' 
*/
data expanded_genres;
    set cast_crew; 

    /* count the number of '}' aka number of genres in the list */
    ed_curly = count(genres, '}');
    do i = 1 to ed_curly;
        /* extract the ith genre in the list of genres */
        genre_info = scan(genres, i, '}');
        /* find the opening position of the ith genre */
        genre_start = find(genre_info, '"name":') + 8;
        /* find the position of ':' within genre_info starting from genre_start 
           aka find the ending position of the ith genre */
        genre_end = find(genre_info, ':', genre_start);
        /* extract the name of the ith genre */
        genre_name = scan(substr(genre_info, genre_start, genre_end - genre_start), 1, ',');
        /* remove double quotations and trailing blanks */
        genre_name = strip(translate(genre_name, ' ', '"'));
        
        /* create a new row for each genre */
        output;
    end;
    
    keep title genre_name cast_name crew_name;
run;

*--------------- SECTION 2: DEFINE THE MACRO;

%macro frequency_calculator(genre_list);
	/* filter the data based on the genre list provided by the user */
    data filtered_genres;
        set expanded_genres;
        where genre_name in (&genre_list);
    run;

    proc sql noprint;
	    /* calculate the total number of movies in the movie database */
        select count(distinct title) into :total_titles
        from joined_data;

        /* count the number of movies with matching crew_name and cast_name for each genre */
        create table genre_relative_frequency as
        select genre_name,
               round(count(distinct title) / &total_titles, 0.01) as relative_frequency
        from filtered_genres
        where crew_name = cast_name
        group by genre_name;
    quit;

    options validvarname=any; *let variable name contain blanks;

	/* rename the variables */
    data clean_frequency;
        set genre_relative_frequency;
        rename genre_name = 'Genre Name'n
               relative_frequency = 'Relative Frequency'n;
    run;
	
	/* print the output */
    proc print data=clean_frequency noobs;
    run;
%mend;







