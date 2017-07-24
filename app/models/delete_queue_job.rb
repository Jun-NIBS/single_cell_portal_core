class DeleteQueueJob < Struct.new(:object)
  # generic class to queue objects for deletion.  Can handle studies & study files

  def perform
    # determine type of delete job
    case object.class.name
      when 'Study'
        # mark for deletion, rename study to free up old name for use, and restrict access by removing owner
        new_name = "DELETE-#{object.data_dir}"
        object.update!(queued_for_deletion: true, public: false, user_id: nil, name: new_name, url_safe_name: new_name)
      when 'StudyFile'
        file_type = object.file_type
        study = object.study

        # reset initialized if needed
        if study.cluster_ordinations_files.empty? || study.expression_matrix_file.nil? || study.metadata_file.nil?
          study.update!(initialized: false)
        end

        # now remove all child objects first to free them up to be re-used.
        case file_type
          when 'Cluster'
            # first check if default cluster needs to be cleared
            if study.default_cluster.name == object.cluster_groups.first.name
              study.default_options[:cluster] = nil
              study.default_options[:annotation] = nil
              study.save
            end

            ClusterGroup.where(study_file_id: object.id, study_id: study.id).delete_all
            DataArray.where(study_file_id: object.id, study_id: study.id).delete_all
          when 'Expression Matrix'
            ExpressionScore.where(study_file_id: object.id, study_id: study.id).delete_all
            DataArray.where(study_file_id: object.id, study_id: study.id).delete_all
          when 'Metadata'
            StudyMetadatum.where(study_file_id: object.id, study_id: study.id).delete_all
          when 'Gene List'
            PrecomputedScore.where(study_file_id: object.id, study_id: study.id).delete_all
          else
            nil
        end

        # queue study file object for deletion
        new_name = "DELETE-#{SecureRandom.uuid}"
        object.update!(queued_for_deletion: true, upload_file_name: new_name, name: new_name, file_type: nil)
    end
  end
end